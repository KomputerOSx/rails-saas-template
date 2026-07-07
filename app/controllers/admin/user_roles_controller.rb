module Admin
  class UserRolesController < BaseController
    before_action { authorize :system, :manage_users?, policy_class: SystemPolicy }
    before_action :set_user

    def create
      role = Role.find(params[:role_id])
      @user.grant_role!(role, granted_by: current_user)
      log_audit(:role_granted, user: @user, resource: role, metadata: { role: role.name })
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: "Granted #{role.name} to #{@user.email}.", type: "success" }
          render turbo_stream: [
            turbo_stream.replace(dom_id(@user, :system_roles_panel), partial: "admin/users/system_roles_panel",
                                  locals: { user: @user, roles: system_roles }),
            turbo_stream.update("flash_messages", partial: "shared/flash")
          ]
        end
        format.html { redirect_to admin_user_path(@user), notice: "Granted #{role.name} to #{@user.email}." }
      end
    end

    def destroy
      role = Role.find(params[:role_id])
      user_role = @user.user_roles.find_by(role: role)

      if user_role&.destroy
        log_audit(:role_revoked, user: @user, resource: role, metadata: { role: role.name })
        respond_to do |format|
          format.turbo_stream do
            flash.now[:toast] = { message: "Revoked #{role.name} from #{@user.email}.", type: "success" }
            render turbo_stream: [
              turbo_stream.replace(dom_id(@user, :system_roles_panel), partial: "admin/users/system_roles_panel",
                                    locals: { user: @user, roles: system_roles }),
              turbo_stream.update("flash_messages", partial: "shared/flash")
            ]
          end
          format.html { redirect_to admin_user_path(@user), notice: "Revoked #{role.name} from #{@user.email}." }
        end
      else
        log_audit(:system_admin_revocation_blocked, user: @user, resource: role, metadata: { role: role.name })
        error_message = "Cannot revoke the platform's last system admin."
        respond_to do |format|
          format.turbo_stream do
            flash.now[:toast] = { message: error_message, type: "error" }
            render turbo_stream: turbo_stream.update("flash_messages", partial: "shared/flash")
          end
          format.html { redirect_to admin_user_path(@user), alert: error_message }
        end
      end
    end

    private

    def set_user
      @user = User.find(params[:user_id])
    end

    def system_roles
      Role.system.order(:name)
    end
  end
end
