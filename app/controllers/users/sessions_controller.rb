class Users::SessionsController < Devise::SessionsController
  def create
    self.resource = warden.authenticate(auth_options)

    if resource
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      log_audit(:login_success, user: resource)
      flash.delete(:notice)
      flash[:toast] = { message: "Signed in successfully.", type: "success" }
      yield resource if block_given?
      respond_with resource, location: after_sign_in_path_for(resource)
    else
      log_audit(:login_failure, user: nil, metadata: { email: params.dig(:user, :email) })
      self.resource = resource_class.new(sign_in_params)
      clean_up_passwords(resource)
      flash.now[:alert] = "Invalid Email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    log_audit(:logout)
    super do
      flash.delete(:notice)
      flash[:toast] = { message: "Signed out successfully.", type: "success" }
    end
  end
end
