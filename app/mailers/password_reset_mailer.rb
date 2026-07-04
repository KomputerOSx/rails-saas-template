class PasswordResetMailer < ApplicationMailer
  def reset_link(user, token, request_details: {})
    @user = user
    @token = token
    @expires_in_minutes = (PasswordResetToken::EXPIRY / 1.minute).to_i
    @request_details = request_details || {}
    @requested_at = parse_requested_at(@request_details[:requested_at])

    mail(to: user.email, subject: "Reset your password")
  end

  private

  def parse_requested_at(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    Time.current
  end
end
