class EmailChangeMailer < ApplicationMailer
  def confirm_old_email(user, code)
    @user = user
    @code = code
    @expires_in_minutes = (User::EMAIL_CHANGE_EXPIRY / 1.minute).to_i

    mail(to: user.email, subject: "Confirm your email change")
  end

  def confirm_new_email(user, code)
    @user = user
    @code = code
    @expires_in_minutes = (User::EMAIL_CHANGE_EXPIRY / 1.minute).to_i

    mail(to: user.unconfirmed_email, subject: "Confirm your new email address")
  end
end
