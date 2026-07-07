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
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: "Invitation sent to #{invitation.email}.", type: "success" }
          render turbo_stream: [
            turbo_stream.replace("pending_invitations_section", partial: "org/invitations/section",
                                  locals: { pending_invitations: pending_invitations }),
            turbo_stream.replace("flash_messages", partial: "shared/flash")
          ]
        end
        format.html { redirect_to org_settings_path, notice: "Invitation sent to #{invitation.email}." }
      end
    end

    def destroy
      invitation = Current.organization.organization_invitations.outstanding.find(params[:id])
      authorize invitation

      invitation.revoke!
      log_audit(:organization_invitation_revoked, resource: Current.organization, metadata: { email: invitation.email })
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: "Invitation revoked.", type: "success" }
          render turbo_stream: [
            turbo_stream.replace("pending_invitations_section", partial: "org/invitations/section",
                                  locals: { pending_invitations: pending_invitations }),
            turbo_stream.replace("flash_messages", partial: "shared/flash")
          ]
        end
        format.html { redirect_to org_settings_path, notice: "Invitation revoked." }
      end
    end

    private

    def pending_invitations
      Current.organization.organization_invitations.outstanding.includes(:role, :invited_by)
    end
  end
end
