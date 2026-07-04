class TwoFactorMailer < ApplicationMailer
  def login_code(user, code, expires_in_minutes:, request_details: {})
    @user = user
    @code = code
    @expires_in_minutes = expires_in_minutes
    @request_details = request_details || {}
    @requested_at = parse_requested_at(@request_details[:requested_at])

    mail(to: user.email, subject: "Your security code")
  end

  private

  def parse_requested_at(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    Time.current
  end
end
