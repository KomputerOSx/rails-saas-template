class ConfirmationMailer < ApplicationMailer
  def confirmation_code(email, code)
    @email = email
    @code = code
    @expires_in_minutes = (User::CONFIRMATION_EXPIRY / 1.minute).to_i

    mail(to: email, subject: "Confirm your email address")
  end
end
