class PasswordResetsController < ApplicationController
  layout "auth"

  allow_unauthenticated_access only: [ :new, :create, :edit, :update ]

  GENERIC_NOTICE = "If that account exists, a password reset link has been sent."
  INVALID_TOKEN_ALERT = "This password reset link is invalid or has expired."
  RESET_REQUEST_WINDOW = 10.minutes
  RESET_REQUESTS_PER_IP = 5
  RESET_REQUESTS_PER_EMAIL = 3

  def new
  end

  def create
    email = normalized_email
    user = email.present? ? User.find_by(email: email) : nil

    log_audit(:password_reset_requested, user: user, metadata: { email: email.presence })

    if reset_request_throttled?(email)
      log_audit(:rate_limit_triggered, user: user, metadata: { scope: "password_reset", email: email.presence })
      redirect_to new_password_reset_path, notice: GENERIC_NOTICE
      return
    end

    if resettable_user?(user)
      _record, raw_token = PasswordResetToken.generate_for!(user, request_ip: request.remote_ip, request_user_agent: request.user_agent)

      PasswordResetMailer.reset_link(user, raw_token, request_details: reset_request_details).deliver_later

      log_audit(:password_reset_link_sent, user: user, metadata: { email: user.email })
    else
      consume_reset_timing
    end

    # Always the same redirect/notice regardless of whether the account exists —
    # prevents user enumeration via response content or timing.
    redirect_to new_password_reset_path, notice: GENERIC_NOTICE
  end

  def edit
    @token = params[:token].to_s
    @password_reset_token = usable_token_for(@token)

    redirect_to new_password_reset_path, alert: INVALID_TOKEN_ALERT unless @password_reset_token
  end

  def update
    @token = params[:token].to_s
    @password_reset_token = usable_token_for(@token)

    unless @password_reset_token
      redirect_to new_password_reset_path, alert: INVALID_TOKEN_ALERT
      return
    end

    user = @password_reset_token.user

    ActiveRecord::Base.transaction do
      unless user.update(password: params[:password], password_confirmation: params[:password_confirmation])
        raise ActiveRecord::Rollback
      end

      user.update!(failed_login_attempts: 0, locked_until: nil)
      user.sessions.destroy_all
      @password_reset_token.consume!
    end

    if user.errors.empty?
      log_audit(:password_reset_completed, user: user, metadata: { email: user.email })
      redirect_to login_path, notice: "Your password has been reset. Log in with your new password."
    else
      log_audit(:password_reset_failed, user: user, metadata: { email: user.email, errors: user.errors.full_messages })
      flash.now[:alert] = user.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def normalized_email
    params[:email].to_s.strip.downcase
  end

  def resettable_user?(user)
    user.present? && user.confirmed? && !user.locked? && !user.disabled?
  end

  def usable_token_for(raw_token)
    token = PasswordResetToken.find_usable(raw_token)
    return nil unless token&.usable?
    return nil unless resettable_user?(token.user)

    token
  end

  def reset_request_throttled?(email)
    ip_throttled = increment_throttle("password_reset:ip:#{request.remote_ip.presence || 'unknown'}") > RESET_REQUESTS_PER_IP
    email_throttled = email.present? && increment_throttle("password_reset:email:#{email}") > RESET_REQUESTS_PER_EMAIL
    ip_throttled || email_throttled
  end

  def increment_throttle(key)
    count = Rails.cache.increment(key, 1, expires_in: RESET_REQUEST_WINDOW)
    return count if count

    Rails.cache.write(key, 1, expires_in: RESET_REQUEST_WINDOW)
    1
  end

  def reset_request_details
    { ip_address: request.remote_ip, user_agent: request.user_agent, requested_at: Time.current.iso8601 }
  end

  # Keeps response timing constant for non-existent/non-resettable accounts.
  def consume_reset_timing
    PasswordResetToken.digest(SecureRandom.urlsafe_base64(PasswordResetToken::TOKEN_BYTES))
  end
end
