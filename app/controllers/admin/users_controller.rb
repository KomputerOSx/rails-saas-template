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
      @memberships = @user.memberships.includes(:organization, :roles)
      # UserRole only accepts system-scoped roles now (app-scoped roles attach to a
      # Membership instead) - this grant UI only ever offers system-scope roles.
      @roles = Role.system.order(:name)
    end

    def update
      @user = User.find(params[:id])
      changes = user_params.to_h.select { |k, v| @user.public_send(k) != v }

      if @user.update(user_params)
        log_audit(:user_updated, user: @user, metadata: { changes: changes }) if changes.any?
        redirect_to admin_user_path(@user), notice: "User updated."
      else
        @roles = Role.system.order(:name)
        flash.now[:alert] = @user.errors.full_messages.join(", ")
        render :show, status: :unprocessable_entity
      end
    end

    def disable
      @user = User.find(params[:id])
      @user.disable!
      log_audit(:user_disabled, user: @user)
      redirect_to admin_user_path(@user), notice: "#{@user.email} has been disabled and signed out everywhere."
    end

    def enable
      @user = User.find(params[:id])
      @user.enable!
      log_audit(:user_enabled, user: @user)
      redirect_to admin_user_path(@user), notice: "#{@user.email} has been re-enabled."
    end

    def send_reset_link
      @user = User.find(params[:id])
      _record, raw_token = PasswordResetToken.generate_for!(@user, request_ip: request.remote_ip, request_user_agent: request.user_agent)
      request_details = { ip_address: request.remote_ip, user_agent: request.user_agent, requested_at: Time.current.iso8601 }
      PasswordResetMailer.reset_link(@user, raw_token, request_details: request_details).deliver_later
      log_audit(:password_reset_link_sent, user: @user, metadata: { email: @user.email, admin_triggered: true })
      redirect_to admin_user_path(@user), notice: "Password reset link sent to #{@user.email}."
    end

    private

    def user_params
      params.require(:user).permit(:first_name, :last_name, :email)
    end
  end
end
