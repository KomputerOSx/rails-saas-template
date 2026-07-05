class SessionsController < ApplicationController
  include InvitationResumption
  include TwoFactorAuthentication
  include LoginCompletable

  layout "auth"

  allow_unauthenticated_access only: [ :new, :create, :two_factor, :verify_two_factor, :resend_two_factor, :email_two_factor_fallback ]
  skip_before_action :enforce_maintenance_mode!
  skip_before_action :enforce_onboarding_gate!

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
      flash.now[:toast] = { message: "Please confirm your email address before logging in. Check your inbox for the confirmation code.", type: "error" }
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
      redirect_to login_path, alert: "Please log in to continue."
      return
    end

    assign_two_factor_view_state(challenge)
  end

  def verify_two_factor
    challenge = two_factor_challenge
    user = challenge&.user
    unless user && challenge
      redirect_to login_path, alert: "Your security code has expired. Please log in again."
      return
    end

    if challenge.expired?
      clear_two_factor_challenge
      redirect_to login_path, alert: "Your security code has expired. Please log in again."
      return
    end

    if valid_two_factor_code?(otp_code_param, challenge)
      challenge.update!(used_at: Time.current)
      trust_two_factor_device_for(user) if params[:remember_device] == "1"
      clear_two_factor_challenge(delete_record: false)
      complete_login_for(user)
    else
      challenge.increment!(:attempts)
      log_audit(:two_factor_failure, user: user, metadata: { attempts: challenge.attempts })

      if challenge.attempts >= TWO_FACTOR_MAX_ATTEMPTS
        clear_two_factor_challenge
        redirect_to login_path, alert: "Too many incorrect codes. Please log in again."
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
      redirect_to login_path, alert: "Please log in to continue."
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
      redirect_to login_path, alert: "Please log in to continue."
      return
    end

    log_audit(:totp_email_fallback_requested, user: user)
    begin_two_factor_for(user, delivery_method: "email")
    redirect_to two_factor_login_path, notice: "A backup code has been emailed to you."
  end

  def destroy
    log_audit(:logout)
    terminate_session
    redirect_to root_path, notice: "Logged out successfully."
  end

  private

  def normalized_login_email
    params[:email].to_s.strip.downcase
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
