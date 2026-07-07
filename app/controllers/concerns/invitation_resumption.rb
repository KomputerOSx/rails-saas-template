module InvitationResumption
  private

  # Completes an OrganizationInvitation that was stashed in the session before the
  # user had to log in or sign up to accept it (see InvitationsController#show).
  # Always clears the stashed token, whether or not it resolves to anything usable.
  def resume_pending_invitation_for(user, token: session[:pending_invitation_token])
    session.delete(:pending_invitation_token)
    return nil if token.blank?

    invitation = OrganizationInvitation.find_usable(token)
    return nil unless invitation && invitation.email.casecmp?(user.email)

    invitation.accept!(user)
    log_audit(:organization_invitation_accepted, user: user, resource: invitation.organization,
      metadata: { invitation_id: invitation.id, role: invitation.role.name })
    invitation
  rescue OrganizationInvitation::MemberLimitReached
    flash[:toast] = { message: "#{invitation.organization.name} is at its plan's member limit. Ask an owner to upgrade before you can join.", type: "error" }
    nil
  end
end
