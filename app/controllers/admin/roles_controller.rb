module Admin
  class RolesController < BaseController
    def index
      @roles = Role.order(:scope, :name).includes(:permissions)
    end

    def show
      @role = Role.find(params[:id])
    end
  end
end
