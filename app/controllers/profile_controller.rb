class ProfileController < ApplicationController
  def show
  end

  def update
    if current_user.update(profile_params)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: "Profile updated successfully.", type: "success" }
          render turbo_stream: [
            turbo_stream.replace(dom_id(current_user, :name_display), partial: "profile/name_display"),
            turbo_stream.update(dom_id(current_user, :dialog), partial: "profile/name_dialog_content"),
            turbo_stream.update("flash_messages", partial: "shared/flash")
          ]
        end
        format.html do
          flash[:toast] = { message: "Profile updated successfully.", type: "success" }
          redirect_to profile_path
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(dom_id(current_user, :dialog), partial: "profile/name_dialog_content"),
                 status: :unprocessable_entity
        end
        format.html { render :show, status: :unprocessable_entity }
      end
    end
  end

  def send_deletion_code
    code = current_user.request_account_deletion_code!
    AccountDeletionMailer.confirm_deletion(current_user, code).deliver_later
    render json: { sent: true }
  end

  def destroy
    typed = params[:typed_confirmation].to_s.strip.downcase
    code  = Array(params[:code]).join.strip

    unless typed == current_user.email.downcase
      flash[:toast] = { message: "Email address did not match. Account not deleted.", type: "error" }
      redirect_to profile_path and return
    end

    unless current_user.verify_account_deletion_code!(code)
      flash[:toast] = { message: "Invalid or expired confirmation code. Account not deleted.", type: "error" }
      redirect_to profile_path and return
    end

    saved_email = current_user.email

    ActiveRecord::Base.transaction do
      # Destroy orgs where this user is the sole owner - the last-owner guard would
      # otherwise abort the cascade when memberships are deleted.
      # Orgs with other owners are left intact; the membership cascade handles removal.
      current_user.organizations.each do |org|
        other_owners = org.membership_roles
          .joins(:role, :membership)
          .where(roles: { scope: "app", name: Role::APP_OWNER })
          .where.not(memberships: { user_id: current_user.id })
        next if other_owners.exists?

        # Bypass the last-owner guard (which fires per-record during cascade) by
        # deleting all membership_roles for this org via SQL before destroying it.
        MembershipRole.joins(:membership)
                      .where(memberships: { organization_id: org.id })
                      .delete_all
        org.destroy!
      end

      current_user.destroy!
    end

    # Sessions are cascade-deleted with the user; just clear the cookie.
    cookies.delete(:session_id)
    log_audit(:user_deleted, user: nil, metadata: { email: saved_email })
    flash[:toast] = { message: "Your account has been deleted.", type: "success" }
    redirect_to root_path
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordInvalid => e
    Rails.logger.error "[AccountDeletion] #{e.class}: #{e.message} user=#{current_user.id}"
    flash[:toast] = { message: "Could not delete account. Please contact support.", type: "error" }
    redirect_to profile_path
  end

  def update_email_preferences
    EmailCampaign::OPTIONAL_CATEGORIES.each do |category|
      if params[:subscribed]&.key?(category)
        current_user.resubscribe_to_email_category!(category)
      else
        current_user.unsubscribe_from_email_category!(category)
      end
    end

    flash[:toast] = { message: "Notification preferences updated.", type: "success" }
    redirect_to profile_path
  end

  def new_totp
    if current_user.totp_enabled?
      redirect_to profile_path, notice: "Authenticator app verification is already enabled."
      return
    end

    # Stash the secret in session so revisiting the page doesn't regenerate
    # a new secret/QR code each time (which would desync an already-scanned app).
    session[:pending_totp_secret] ||= User.generate_totp_secret
    @totp_secret = session[:pending_totp_secret]
    build_totp_qr
  end

  def create_totp
    @totp_secret = session[:pending_totp_secret]

    unless @totp_secret.present?
      redirect_to new_profile_totp_path, alert: "Start authenticator app setup again."
      return
    end

    unless current_user.authenticate(params[:current_password])
      build_totp_qr
      flash.now[:alert] = "Current password is incorrect."
      render :new_totp, status: :unprocessable_entity
      return
    end

    unless current_user.valid_totp_code?(otp_code_param, @totp_secret)
      build_totp_qr
      flash.now[:alert] = "Authenticator code is invalid. Please try again."
      render :new_totp, status: :unprocessable_entity
      return
    end

    current_user.enable_totp!(@totp_secret)
    session.delete(:pending_totp_secret)

    log_audit(:totp_enabled)

    redirect_to profile_path, notice: "Authenticator app verification has been enabled."
  end

  def destroy_totp
    unless current_user.totp_enabled?
      redirect_to profile_path, notice: "Authenticator app verification is not enabled."
      return
    end

    unless current_user.authenticate(params[:current_password])
      redirect_to profile_path, alert: "Current password is incorrect."
      return
    end

    current_session_id = Current.session&.id
    current_user.disable_totp!
    # Force re-verification everywhere except the browser that just proved the password.
    current_user.sessions.where.not(id: current_session_id).destroy_all

    log_audit(:totp_disabled, metadata: { other_sessions_destroyed: true })

    redirect_to profile_path, notice: "Authenticator app verification has been disabled."
  end

  private

  def profile_params
    params.require(:user).permit(:first_name, :last_name)
  end

  def build_totp_qr
    @totp_qr_svg = RQRCode::QRCode.new(current_user.totp_provisioning_uri(@totp_secret)).as_svg(
      module_size: 4, standalone: true, use_path: true
    )
  end
end
