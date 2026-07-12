class OwnerDemotionMailer < ApplicationMailer
  def confirm_demotion(target_user, initiator, organization, code)
    @target = target_user
    @initiator = initiator
    @organization = organization
    @self_initiated = target_user == initiator
    @code = code
    mail(to: target_user.email, subject: "Confirm owner demotion")
  end
end
