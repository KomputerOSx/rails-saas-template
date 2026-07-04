class ProfileController < ApplicationController
  def show
  end

  def update
    if current_user.update(profile_params)
      flash[:toast] = { message: "Profile updated successfully.", type: "success" }
      redirect_to profile_path
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    log_audit(:user_deleted, metadata: { email: current_user.email })
    terminate_session
    current_user.destroy
    flash[:toast] = { message: "Your account has been deleted.", type: "success" }
    redirect_to root_path
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
