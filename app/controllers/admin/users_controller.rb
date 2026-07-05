module Admin
  class UsersController < BaseController
    def index
      @q    = params[:q].to_s.strip
      @role = params[:role].to_s.strip

      @users = User.order(:email).includes(:roles)
      @users = @users.where("email LIKE ?", "%#{User.sanitize_sql_like(@q)}%") if @q.present?
      @users = @users.joins(:roles).where(roles: { name: @role }).distinct if @role.present?

      @roles = Role.order(:name)
    end

    def show
      @user = User.find(params[:id])
      # UserRole only accepts system-scoped roles now (app-scoped roles attach to a
      # Membership instead) — this grant UI only ever offers system-scope roles.
      @roles = Role.system.order(:name)
    end
  end
end
