module Admin
  class RolesController < BaseController
    before_action { authorize :system, :manage_roles?, policy_class: SystemPolicy }
    before_action :set_role, only: [ :show, :edit, :update, :destroy ]

    def index
      @q     = params[:q].to_s.strip
      @scope = params[:scope].to_s.strip

      @roles = Role.order(:scope, :name).includes(:permissions)
      @roles = @roles.where("name LIKE ?", "%#{Role.sanitize_sql_like(@q)}%") if @q.present?
      @roles = @roles.where(scope: @scope) if Role.scopes.key?(@scope)
    end

    def show
    end

    def new
      @role = Role.new(scope: :app)
      @permissions = Permission.order(:key)
    end

    def create
      @role = Role.new(role_params)

      if @role.save
        log_audit(:role_created, resource: @role, metadata: { name: @role.name, scope: @role.scope })
        redirect_to admin_role_path(@role), notice: "Role created."
      else
        @permissions = Permission.order(:key)
        flash.now[:alert] = @role.errors.full_messages.join(", ")
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @permissions = Permission.order(:key)
    end

    def update
      if @role.update(role_update_params)
        log_audit(:role_updated, resource: @role, metadata: { name: @role.name })
        redirect_to admin_role_path(@role), notice: "Role updated."
      else
        @permissions = Permission.order(:key)
        flash.now[:alert] = @role.errors.full_messages.join(", ")
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      name, scope = @role.name, @role.scope

      if @role.destroy
        log_audit(:role_deleted, metadata: { name: name, scope: scope })
        redirect_to admin_roles_path, notice: "Role deleted."
      else
        redirect_to admin_role_path(@role), alert: @role.errors.full_messages.join(", ")
      end
    end

    private

    def set_role
      @role = Role.find(params[:id])
    end

    def role_params
      params.require(:role).permit(:name, :description, :scope, permission_ids: [])
    end

    # `scope` is intentionally excluded on update: a role already granted via UserRole
    # (system-scoped) or MembershipRole (app-scoped) has that scope validated on the join
    # row, so changing it after the fact would orphan existing grants. Scope is only
    # choosable at creation time.
    def role_update_params
      params.require(:role).permit(:name, :description, permission_ids: [])
    end
  end
end
