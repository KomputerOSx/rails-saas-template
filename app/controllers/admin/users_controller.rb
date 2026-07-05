module Admin
  class UsersController < BaseController
    def index
      @users = User.order(:email).includes(:roles)
    end

    def show
      @user = User.find(params[:id])
      # UserRole only accepts system-scoped roles now (app-scoped roles attach to a
      # Membership instead) — this grant UI only ever offers system-scope roles.
      @roles = Role.system.order(:name)
    end
  end
end
