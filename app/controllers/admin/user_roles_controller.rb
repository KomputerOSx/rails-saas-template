module Admin
  class UserRolesController < BaseController
    before_action :set_user

    def create
      role = Role.find(params[:role_id])
      @user.grant_role!(role, granted_by: current_user)
      log_audit(:role_granted, user: @user, resource: role, metadata: { role: role.name })
      redirect_to admin_user_path(@user), notice: "Granted #{role.name} to #{@user.email}."
    end

    def destroy
      role = Role.find(params[:role_id])
      @user.revoke_role!(role)
      log_audit(:role_revoked, user: @user, resource: role, metadata: { role: role.name })
      redirect_to admin_user_path(@user), notice: "Revoked #{role.name} from #{@user.email}."
    end

    private

    def set_user
      @user = User.find(params[:user_id])
    end
  end
end
