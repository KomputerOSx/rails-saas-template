module Org
  class InvitationsController < BaseController
    def create
      authorize Current.organization, :create?, policy_class: OrganizationInvitationPolicy

      role = Role.find_by!(scope: :app, name: Role::APP_USER) # invite form always grants `user`; promotion is a separate action
      invitation, raw_token = OrganizationInvitation.generate_for!(
        organization: Current.organization, email: params[:email], role: role, invited_by: current_user
      )
      OrganizationInvitationMailer.invite(invitation, raw_token).deliver_later
      log_audit(:organization_invitation_sent, resource: Current.organization, metadata: { email: invitation.email })
      redirect_to org_settings_path, notice: "Invitation sent to #{invitation.email}."
    end

    def destroy
      invitation = Current.organization.organization_invitations.outstanding.find(params[:id])
      authorize invitation

      invitation.revoke!
      log_audit(:organization_invitation_revoked, resource: Current.organization, metadata: { email: invitation.email })
      redirect_to org_settings_path, notice: "Invitation revoked."
    end
  end
end
