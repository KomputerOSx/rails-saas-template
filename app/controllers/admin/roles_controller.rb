module Admin
  class RolesController < BaseController
    def index
      @q     = params[:q].to_s.strip
      @scope = params[:scope].to_s.strip

      @roles = Role.order(:scope, :name).includes(:permissions)
      @roles = @roles.where("name LIKE ?", "%#{Role.sanitize_sql_like(@q)}%") if @q.present?
      @roles = @roles.where(scope: @scope) if Role.scopes.key?(@scope)
    end

    def show
      @role = Role.find(params[:id])
    end
  end
end
