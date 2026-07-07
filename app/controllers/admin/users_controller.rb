module Admin
  class UsersController < BaseController
    before_action { authorize :system, :manage_users?, policy_class: SystemPolicy }

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
        respond_to do |format|
          format.turbo_stream do
            flash.now[:toast] = { message: "User updated.", type: "success" }
            render turbo_stream: [
              turbo_stream.replace(dom_id(@user, :full_name_heading), partial: "admin/users/full_name_heading", locals: { user: @user }),
              turbo_stream.replace(dom_id(@user, :email_display), partial: "admin/users/email_display", locals: { user: @user }),
              turbo_stream.replace(dom_id(@user, :first_name_display), partial: "admin/users/first_name_display", locals: { user: @user }),
              turbo_stream.replace(dom_id(@user, :last_name_display), partial: "admin/users/last_name_display", locals: { user: @user }),
              turbo_stream.update(dom_id(@user, :dialog), partial: "admin/users/info_dialog_content", locals: { user: @user }),
              turbo_stream.update("flash_messages", partial: "shared/flash")
            ]
          end
          format.html { redirect_to admin_user_path(@user), notice: "User updated." }
        end
      else
        @memberships = @user.memberships.includes(:organization, :roles)
        @roles = Role.system.order(:name)
        flash.now[:alert] = @user.errors.full_messages.join(", ")
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update(dom_id(@user, :dialog), partial: "admin/users/info_dialog_content", locals: { user: @user }),
                   status: :unprocessable_entity
          end
          format.html { render :show, status: :unprocessable_entity }
        end
      end
    end

    def disable
      @user = User.find(params[:id])
      @user.disable!
      log_audit(:user_disabled, user: @user)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: "#{@user.email} has been disabled and signed out everywhere.", type: "success" }
          render turbo_stream: [
            turbo_stream.replace(dom_id(@user, :status_badge), partial: "admin/users/status_badge", locals: { user: @user }),
            turbo_stream.replace(dom_id(@user, :danger_zone), partial: "admin/users/danger_zone", locals: { user: @user }),
            turbo_stream.update("flash_messages", partial: "shared/flash")
          ]
        end
        format.html { redirect_to admin_user_path(@user), notice: "#{@user.email} has been disabled and signed out everywhere." }
      end
    end

    def enable
      @user = User.find(params[:id])
      @user.enable!
      log_audit(:user_enabled, user: @user)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: "#{@user.email} has been re-enabled.", type: "success" }
          render turbo_stream: [
            turbo_stream.replace(dom_id(@user, :status_badge), partial: "admin/users/status_badge", locals: { user: @user }),
            turbo_stream.replace(dom_id(@user, :danger_zone), partial: "admin/users/danger_zone", locals: { user: @user }),
            turbo_stream.update("flash_messages", partial: "shared/flash")
          ]
        end
        format.html { redirect_to admin_user_path(@user), notice: "#{@user.email} has been re-enabled." }
      end
    end

    def send_reset_link
      @user = User.find(params[:id])
      _record, raw_token = PasswordResetToken.generate_for!(@user, request_ip: request.remote_ip, request_user_agent: request.user_agent)
      request_details = { ip_address: request.remote_ip, user_agent: request.user_agent, requested_at: Time.current.iso8601 }
      PasswordResetMailer.reset_link(@user, raw_token, request_details: request_details).deliver_later
      log_audit(:password_reset_link_sent, user: @user, metadata: { email: @user.email, admin_triggered: true })
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: "Password reset link sent to #{@user.email}.", type: "success" }
          render turbo_stream: turbo_stream.update("flash_messages", partial: "shared/flash")
        end
        format.html { redirect_to admin_user_path(@user), notice: "Password reset link sent to #{@user.email}." }
      end
    end

    private

    def user_params
      params.require(:user).permit(:first_name, :last_name, :email)
    end
  end
end
