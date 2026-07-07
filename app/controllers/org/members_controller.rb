module Org
  class MembersController < BaseController
    before_action :set_membership, only: [ :destroy, :promote, :demote ]
    before_action :authorize_membership, only: [ :destroy, :promote, :demote ]
    before_action :reject_owner_target, only: [ :promote, :demote ]

    def destroy
      membership_dom_id = dom_id(@membership)

      if @membership.destroy
        log_audit(:membership_destroyed, resource: Current.organization, metadata: { removed_user_id: @membership.user_id })
        respond_to do |format|
          format.turbo_stream do
            flash.now[:toast] = { message: "Member removed.", type: "success" }
            render turbo_stream: [
              turbo_stream.remove(membership_dom_id),
              turbo_stream.replace("flash_messages", partial: "shared/flash")
            ]
          end
          format.html { redirect_to org_settings_path, notice: "Member removed." }
        end
      else
        log_audit(:owner_removal_blocked, resource: Current.organization, metadata: { target_user_id: @membership.user_id })
        respond_to do |format|
          format.turbo_stream do
            flash.now[:toast] = { message: "Cannot remove the organization's last owner.", type: "error" }
            render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flash")
          end
          format.html { redirect_to org_settings_path, alert: "Cannot remove the organization's last owner." }
        end
      end
    end

    def leave
      skip_authorization # self-removal is always allowed, no permission required

      organization = Current.organization
      membership = organization.memberships.find_by!(user: current_user)

      if membership.destroy
        log_audit(:membership_destroyed, resource: organization, metadata: { removed_user_id: current_user.id, self_removal: true })
        redirect_to dashboard_path, notice: "You have left #{organization.name}."
      else
        log_audit(:owner_removal_blocked, resource: organization, metadata: { target_user_id: current_user.id, self_removal: true })
        redirect_to org_settings_path, alert: "You can't leave! You're the organization's last owner."
      end
    end

    def promote
      @membership.grant_role!(Role.find_by!(scope: :app, name: Role::APP_ADMIN), granted_by: current_user)
      @membership.revoke_role!(Role.find_by!(scope: :app, name: Role::APP_USER))
      log_audit(:role_granted, resource: Current.organization, metadata: { membership_id: @membership.id, role: Role::APP_ADMIN })
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: "Member promoted to admin.", type: "success" }
          render turbo_stream: [
            turbo_stream.replace(dom_id(@membership), partial: "org/members/membership_row", locals: { membership: @membership }),
            turbo_stream.replace("flash_messages", partial: "shared/flash")
          ]
        end
        format.html { redirect_to org_settings_path, notice: "Member promoted to admin." }
      end
    end

    def demote
      @membership.grant_role!(Role.find_by!(scope: :app, name: Role::APP_USER), granted_by: current_user)
      @membership.revoke_role!(Role.find_by!(scope: :app, name: Role::APP_ADMIN))
      log_audit(:role_revoked, resource: Current.organization, metadata: { membership_id: @membership.id, role: Role::APP_ADMIN })
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: "Member demoted to user.", type: "success" }
          render turbo_stream: [
            turbo_stream.replace(dom_id(@membership), partial: "org/members/membership_row", locals: { membership: @membership }),
            turbo_stream.replace("flash_messages", partial: "shared/flash")
          ]
        end
        format.html { redirect_to org_settings_path, notice: "Member demoted to user." }
      end
    end

    private

    def set_membership
      @membership = Current.organization.memberships.find(params[:id])
    end

    # `authorize` defaults to checking "#{action_name}?" on MembershipPolicy,
    # i.e. `destroy?`/`promote?`/`demote?` - one method per action, no query needed.
    def authorize_membership
      authorize @membership
    end

    def reject_owner_target
      return unless @membership.has_role?(Role::APP_OWNER, scope: :app)

      # Ownership transfer isn't implemented in this template - see the extension-point
      # comment in MembershipRole#prevent_removing_last_owner for how it would work.
      redirect_to org_settings_path, alert: "Ownership changes aren't supported in this template."
    end
  end
end
