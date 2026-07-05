class AccountDeletionMailer < ApplicationMailer
  def confirm_deletion(user, code)
    @user = user
    @code = code
    mail(to: user.email, subject: "Confirm account deletion")
  end
end
