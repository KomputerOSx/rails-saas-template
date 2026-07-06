module Admin
  class PermissionsController < BaseController
    before_action :set_permission, only: [ :show, :edit, :update, :destroy ]

    def index
      @q = params[:q].to_s.strip

      @permissions = Permission.order(:key).includes(:roles)
      @permissions = @permissions.where("key LIKE ?", "%#{Permission.sanitize_sql_like(@q)}%") if @q.present?
    end

    def show
    end

    def new
      @permission = Permission.new
    end

    def create
      @permission = Permission.new(permission_params)

      if @permission.save
        log_audit(:permission_created, resource: @permission, metadata: { key: @permission.key })
        redirect_to admin_permission_path(@permission), notice: "Permission created."
      else
        flash.now[:alert] = @permission.errors.full_messages.join(", ")
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @permission.update(permission_params)
        log_audit(:permission_updated, resource: @permission, metadata: { key: @permission.key })
        redirect_to admin_permission_path(@permission), notice: "Permission updated."
      else
        flash.now[:alert] = @permission.errors.full_messages.join(", ")
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      key = @permission.key
      @permission.destroy
      log_audit(:permission_deleted, metadata: { key: key })
      redirect_to admin_permissions_path, notice: "Permission deleted."
    end

    private

    def set_permission
      @permission = Permission.find(params[:id])
    end

    def permission_params
      params.require(:permission).permit(:key, :description)
    end
  end
end
