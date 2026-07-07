module TwoFactorAuthentication
  extend ActiveSupport::Concern

  TWO_FACTOR_EXPIRY = 10.minutes
  TWO_FACTOR_MAX_ATTEMPTS = 5
  TRUSTED_TWO_FACTOR_DURATION = 24.hours
  TRUSTED_TWO_FACTOR_COOKIE = :trusted_two_factor

  private

  def begin_two_factor_for(user, delivery_method: nil)
    delivery_method ||= user.totp_enabled? ? "totp" : "email"
    code = delivery_method == "email" ? format("%06d", SecureRandom.random_number(1_000_000)) : nil
    challenge_id = SecureRandom.urlsafe_base64(24)

    pending_invitation_token = session[:pending_invitation_token]
    clear_two_factor_challenge
    reset_session # regenerate session id - defends against session fixation
    session[:pending_invitation_token] = pending_invitation_token if pending_invitation_token
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
      # :lax, not :strict - this cookie is also read from OmniauthCallbacksController#create,
      # which runs on the cross-site-initiated redirect landing from the OAuth provider (see
      # the same reasoning in Authentication#start_new_session_for).
      same_site: :lax,
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
end
