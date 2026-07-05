class OrganizationInvitationMailer < ApplicationMailer
  def invite(invitation, raw_token)
    @invitation = invitation
    @raw_token = raw_token
    @expires_in_days = (OrganizationInvitation::EXPIRY / 1.day).to_i

    mail(to: invitation.email, subject: "You've been invited to join #{invitation.organization.name}")
  end
end
