module Admin
  class UsersController < BaseController
    def index
      @users = User.order(:email).includes(:roles)
    end

    def show
      @user = User.find(params[:id])
      @roles = Role.order(:scope, :name)
    end
  end
end
