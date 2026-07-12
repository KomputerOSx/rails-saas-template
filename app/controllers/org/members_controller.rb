module Org
  class MembersController < BaseController
    before_action :set_membership, only: [
      :destroy, :promote, :demote, :promote_to_owner, :send_promotion_code, :demote_owner, :send_owner_demotion_code
    ]
    before_action :authorize_membership, only: [ :destroy, :promote, :demote ]
    before_action :reject_owner_target, only: [ :destroy, :promote, :demote ]
    before_action :authorize_promote_to_owner, only: [ :promote_to_owner, :send_promotion_code ]
    before_action :reject_existing_owner_target, only: [ :promote_to_owner, :send_promotion_code ]
    before_action :authorize_demote_owner, only: [ :demote_owner, :send_owner_demotion_code ]
    before_action :reject_non_owner_target, only: [ :demote_owner, :send_owner_demotion_code ]

    def destroy
      membership_dom_id = dom_id(@membership)

      if @membership.destroy
        log_audit(:membership_destroyed, resource: Current.organization, metadata: { removed_user_id: @membership.user_id })
        respond_to do |format|
          format.turbo_stream do
            flash.now[:toast] = { message: "Member removed.", type: "success" }
            render turbo_stream: [
              turbo_stream.remove(membership_dom_id),
              turbo_stream.update("flash_messages", partial: "shared/flash")
            ]
          end
          format.html { redirect_to org_settings_path, notice: "Member removed." }
        end
      else
        log_audit(:owner_removal_blocked, resource: Current.organization, metadata: { target_user_id: @membership.user_id })
        respond_to do |format|
          format.turbo_stream do
            flash.now[:toast] = { message: "Cannot remove the organization's last owner.", type: "error" }
            render turbo_stream: turbo_stream.update("flash_messages", partial: "shared/flash")
          end
          format.html { redirect_to org_settings_path, alert: "Cannot remove the organization's last owner." }
        end
      end
    end

    def leave
      skip_authorization # self-removal is always allowed, no permission required

      organization = Current.organization
      membership = organization.memberships.find_by!(user: current_user)

      if membership.has_role?(Role::APP_OWNER, scope: :app)
        log_audit(:owner_removal_blocked, resource: organization, metadata: { target_user_id: current_user.id, self_removal: true })
        redirect_to org_settings_path, alert: "Step down as owner before leaving the organization." and return
      end

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
            turbo_stream.replace(dom_id(@membership, :role_badge), partial: "org/members/role_badge", locals: { membership: @membership }),
            turbo_stream.update(dom_id(@membership, :dialog), partial: "org/members/edit_dialog_content", locals: { membership: @membership }),
            turbo_stream.update("flash_messages", partial: "shared/flash")
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
            turbo_stream.replace(dom_id(@membership, :role_badge), partial: "org/members/role_badge", locals: { membership: @membership }),
            turbo_stream.update(dom_id(@membership, :dialog), partial: "org/members/edit_dialog_content", locals: { membership: @membership }),
            turbo_stream.update("flash_messages", partial: "shared/flash")
          ]
        end
        format.html { redirect_to org_settings_path, notice: "Member demoted to user." }
      end
    end

    def send_promotion_code
      code = current_user.request_ownership_promotion_code!
      OwnershipPromotionMailer.confirm_promotion(current_user, @membership, code).deliver_later
      render json: { sent: true }
    end

    def promote_to_owner
      typed = params[:typed_confirmation].to_s.strip.downcase
      code  = Array(params[:code]).join.strip

      unless typed == @membership.user.email.downcase
        redirect_to org_settings_path, alert: "Email address did not match. Member not promoted." and return
      end

      unless current_user.verify_ownership_promotion_code!(code)
        redirect_to org_settings_path, alert: "Invalid or expired confirmation code. Member not promoted." and return
      end

      @membership.grant_role!(Role.find_by!(scope: :app, name: Role::APP_OWNER), granted_by: current_user)
      log_audit(:owner_promoted, resource: Current.organization, metadata: { membership_id: @membership.id, target_user_id: @membership.user_id })

      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: "#{@membership.user.email} is now an owner.", type: "success" }
          render turbo_stream: [
            turbo_stream.replace(dom_id(@membership), partial: "org/members/membership_row", locals: { membership: @membership.reload, show_actions: true }),
            turbo_stream.update("flash_messages", partial: "shared/flash")
          ]
        end
        format.html { redirect_to org_settings_path, notice: "#{@membership.user.email} is now an owner." }
      end
    end

    # Sends the demotion confirmation code to the TARGET being demoted (`@membership.user`),
    # never to the acting user - this holds whether an owner is stepping themselves down or
    # another owner initiated it, so ownership can't be stripped without the target's own
    # inbox confirming it.
    def send_owner_demotion_code
      code = @membership.user.request_owner_demotion_code!
      OwnerDemotionMailer.confirm_demotion(@membership.user, current_user, Current.organization, code).deliver_later
      render json: { sent: true }
    end

    def demote_owner
      typed = params[:typed_confirmation].to_s.strip.downcase
      code  = Array(params[:code]).join.strip

      unless typed == @membership.user.email.downcase
        redirect_to org_settings_path, alert: "Email address did not match. Member not demoted." and return
      end

      unless @membership.user.verify_owner_demotion_code!(code)
        redirect_to org_settings_path, alert: "Invalid or expired confirmation code. Member not demoted." and return
      end

      owner_role = Role.find_by!(scope: :app, name: Role::APP_OWNER)

      if @membership.revoke_role!(owner_role)
        @membership.grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_ADMIN), granted_by: current_user)
        log_audit(:owner_demoted, resource: Current.organization,
          metadata: { membership_id: @membership.id, target_user_id: @membership.user_id, self_initiated: @membership.user_id == current_user.id })

        respond_to do |format|
          format.turbo_stream do
            flash.now[:toast] = { message: "#{@membership.user.email} is now an admin.", type: "success" }
            render turbo_stream: [
              turbo_stream.replace(dom_id(@membership), partial: "org/members/membership_row", locals: { membership: @membership.reload, show_actions: true }),
              turbo_stream.update("flash_messages", partial: "shared/flash")
            ]
          end
          format.html { redirect_to org_settings_path, notice: "#{@membership.user.email} is now an admin." }
        end
      else
        log_audit(:owner_removal_blocked, resource: Current.organization, metadata: { target_user_id: @membership.user_id })
        respond_to do |format|
          format.turbo_stream do
            flash.now[:toast] = { message: "Cannot demote the organization's last owner.", type: "error" }
            render turbo_stream: turbo_stream.update("flash_messages", partial: "shared/flash")
          end
          format.html { redirect_to org_settings_path, alert: "Cannot demote the organization's last owner." }
        end
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

      if action_name == "destroy"
        # Owners can never be force-removed, even by another owner - #demote_owner (code-
        # confirmed, sent to the target) is the only way to strip ownership; once demoted,
        # the membership can be removed normally.
        log_audit(:owner_removal_blocked, resource: Current.organization, metadata: { target_user_id: @membership.user_id })
        redirect_to org_settings_path, alert: "Owners can't be removed directly. Demote them to admin first."
      else
        # The admin/user promote-demote toggle doesn't apply to owners; see #promote_to_owner
        # and #demote_owner for the only supported ownership changes.
        redirect_to org_settings_path, alert: "Owners can't be promoted or demoted between admin and user."
      end
    end

    def authorize_promote_to_owner
      authorize @membership, :promote_to_owner?
    end

    def reject_existing_owner_target
      return unless @membership.has_role?(Role::APP_OWNER, scope: :app)

      redirect_to org_settings_path, alert: "#{@membership.user.email} is already an owner."
    end

    def authorize_demote_owner
      authorize @membership, :demote_owner?
    end

    def reject_non_owner_target
      return if @membership.has_role?(Role::APP_OWNER, scope: :app)

      redirect_to org_settings_path, alert: "#{@membership.user.email} isn't an owner."
    end
  end
end
