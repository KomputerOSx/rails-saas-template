class OwnershipPromotionMailer < ApplicationMailer
  def confirm_promotion(user, membership, code)
    @user = user
    @target = membership.user
    @organization = membership.organization
    @code = code
    mail(to: user.email, subject: "Confirm ownership promotion")
  end
end
