class SessionsController < ApplicationController
  layout "auth"

  allow_unauthenticated_access only: [ :new, :create, :two_factor, :verify_two_factor, :resend_two_factor, :email_two_factor_fallback ]

  TWO_FACTOR_EXPIRY = 10.minutes
  TWO_FACTOR_MAX_ATTEMPTS = 5
  TRUSTED_TWO_FACTOR_DURATION = 24.hours
  TRUSTED_TWO_FACTOR_COOKIE = :trusted_two_factor
  DUMMY_PASSWORD_DIGEST = BCrypt::Password.create("not-a-real-password")

  def new
    redirect_to dashboard_path if authenticated?
  end

  def create
    email = normalized_login_email
    user = email.present? ? User.find_by(email: email) : nil

    if user&.locked?
      log_audit(:login_failure, user: user, metadata: { email: email, reason: "account_locked" })
      consume_password_timing(params[:password])
      render_invalid_login
      return
    end

    authenticated = if user
      user.authenticate(params[:password])
    else
      consume_password_timing(params[:password])
      false
    end

    sleep(rand(0.1..0.5)) unless authenticated

    unless authenticated
      user&.increment_failed_login!
      log_audit(:login_failure, user: user, metadata: { email: email, attempts: user&.failed_login_attempts || 0 })
      render_invalid_login
      return
    end

    unless user.confirmed?
      log_audit(:login_failure, user: user, metadata: { email: email, reason: "unconfirmed" })
      flash.now[:toast] = { message: "Please confirm your email address before signing in. Check your inbox for the confirmation code.", type: "error" }
      render :new, status: :unprocessable_entity
      return
    end

    if user.totp_enabled? && !trusted_two_factor_device?(user)
      begin_two_factor_for(user)
      user.reset_failed_login!
      redirect_to two_factor_login_path, notice: "Enter the code from your authenticator app."
    else
      user.reset_failed_login!
      complete_login_for(user, skipped_two_factor: true)
    end
  end

  def two_factor
    challenge = two_factor_challenge
    unless challenge&.user
      redirect_to login_path, alert: "Please sign in to continue."
      return
    end

    assign_two_factor_view_state(challenge)
  end

  def verify_two_factor
    challenge = two_factor_challenge
    user = challenge&.user
    unless user && challenge
      redirect_to login_path, alert: "Your security code has expired. Please sign in again."
      return
    end

    if challenge.expired?
      clear_two_factor_challenge
      redirect_to login_path, alert: "Your security code has expired. Please sign in again."
      return
    end

    if valid_two_factor_code?(params[:code], challenge)
      challenge.update!(used_at: Time.current)
      trust_two_factor_device_for(user) if params[:remember_device] == "1"
      clear_two_factor_challenge(delete_record: false)
      complete_login_for(user)
    else
      challenge.increment!(:attempts)
      log_audit(:two_factor_failure, user: user, metadata: { attempts: challenge.attempts })

      if challenge.attempts >= TWO_FACTOR_MAX_ATTEMPTS
        clear_two_factor_challenge
        redirect_to login_path, alert: "Too many incorrect codes. Please sign in again."
      else
        assign_two_factor_view_state(challenge)
        flash.now[:alert] = "Invalid code. Please try again."
        render :two_factor, status: :unprocessable_entity
      end
    end
  end

  def resend_two_factor
    challenge = two_factor_challenge
    user = challenge&.user
    unless user && challenge
      redirect_to login_path, alert: "Please sign in to continue."
      return
    end

    if challenge.delivery_method_totp?
      redirect_to two_factor_login_path, alert: "Use your authenticator app, or request an email code instead."
      return
    end

    begin_two_factor_for(user)
    redirect_to two_factor_login_path, notice: "A new code has been sent to your email."
  end

  # Recovery path for a user who has TOTP enabled but has lost their device.
  def email_two_factor_fallback
    challenge = two_factor_challenge
    user = challenge&.user
    unless user && challenge&.delivery_method_totp?
      redirect_to login_path, alert: "Please sign in to continue."
      return
    end

    log_audit(:totp_email_fallback_requested, user: user)
    begin_two_factor_for(user, delivery_method: "email")
    redirect_to two_factor_login_path, notice: "A backup code has been emailed to you."
  end

  def destroy
    log_audit(:logout)
    terminate_session
    redirect_to root_path, notice: "Signed out successfully."
  end

  private

  def normalized_login_email
    params[:email].to_s.strip.downcase
  end

  def begin_two_factor_for(user, delivery_method: nil)
    delivery_method ||= user.totp_enabled? ? "totp" : "email"
    code = delivery_method == "email" ? format("%06d", SecureRandom.random_number(1_000_000)) : nil
    challenge_id = SecureRandom.urlsafe_base64(24)

    clear_two_factor_challenge
    reset_session # regenerate session id — defends against session fixation
    session[:two_factor_challenge_id] = challenge_id

    TwoFactorChallenge.create!(
      user: user,
      challenge_id: challenge_id,
      code_digest: (two_factor_digest(code) if code),
      expires_at: TWO_FACTOR_EXPIRY.from_now,
      attempts: 0,
      delivery_method: delivery_method,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if delivery_method == "email"
      TwoFactorMailer.login_code(user, code, expires_in_minutes: (TWO_FACTOR_EXPIRY / 1.minute).to_i,
        request_details: two_factor_request_details).deliver_later
    end

    log_audit(:two_factor_challenge_sent, user: user, metadata: { delivery_method: delivery_method })
  end

  def complete_login_for(user, skipped_two_factor: false)
    user.update(last_sign_in_at: Time.current)
    start_new_session_for(user)

    log_audit(:two_factor_success, user: user) unless skipped_two_factor
    log_audit(:login_success, user: user, metadata: { skipped_two_factor: skipped_two_factor })

    redirect_to dashboard_path, notice: "Signed in successfully."
  end

  def valid_two_factor_code?(code, challenge)
    return challenge.user.verify_totp!(code) if challenge.delivery_method_totp?

    submitted = code.to_s.gsub(/\D/, "")
    return false unless submitted.length == 6

    ActiveSupport::SecurityUtils.secure_compare(two_factor_digest(submitted), challenge.code_digest.to_s)
  end

  def assign_two_factor_view_state(challenge)
    @two_factor_delivery_method = challenge.delivery_method
    @two_factor_email = challenge.user.email
  end

  def two_factor_digest(code)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, code.to_s)
  end

  def trusted_two_factor_device?(user)
    payload = cookies.encrypted[TRUSTED_TWO_FACTOR_COOKIE]
    data = JSON.parse(payload.to_s)
    return false unless data["user_id"].to_i == user.id
    return false unless data["expires_at"].present? && Time.iso8601(data["expires_at"]).future?

    ActiveSupport::SecurityUtils.secure_compare(data["verifier"].to_s, trusted_two_factor_verifier(user))
  rescue ArgumentError, JSON::ParserError, TypeError
    false
  end

  def trust_two_factor_device_for(user)
    expires_at = TRUSTED_TWO_FACTOR_DURATION.from_now
    cookies.encrypted[TRUSTED_TWO_FACTOR_COOKIE] = {
      value: { user_id: user.id, verifier: trusted_two_factor_verifier(user), expires_at: expires_at.iso8601 }.to_json,
      expires: expires_at,
      httponly: true,
      same_site: :strict,
      secure: Rails.env.production?
    }
  end

  # Binding the verifier to password_digest means changing the password
  # auto-invalidates every trusted-device cookie for that user.
  def trusted_two_factor_verifier(user)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base,
      [ user.id, user.password_digest, request.user_agent.to_s ].join(":"))
  end

  def clear_two_factor_challenge(delete_record: true)
    if delete_record && session[:two_factor_challenge_id].present?
      TwoFactorChallenge.where(challenge_id: session[:two_factor_challenge_id]).delete_all
    end
    session.delete(:two_factor_challenge_id)
  end

  def two_factor_challenge
    challenge_id = session[:two_factor_challenge_id]
    return nil if challenge_id.blank?

    TwoFactorChallenge.active.find_by(challenge_id: challenge_id)
  end

  def two_factor_request_details
    { ip_address: request.remote_ip, user_agent: request.user_agent, requested_at: Time.current.iso8601 }
  end

  # Always pays the bcrypt cost, even when the email doesn't resolve to a
  # real user, so response timing can't be used to enumerate accounts.
  def consume_password_timing(password)
    DUMMY_PASSWORD_DIGEST.is_password?(password.to_s)
  end

  def render_invalid_login
    flash.now[:alert] = "Invalid email or password."
    render :new, status: :unprocessable_entity
  end
end
