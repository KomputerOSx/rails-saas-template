class Users::PasswordsController < Devise::PasswordsController
  def create
    super do |resource|
      log_audit(:password_reset_requested, user: nil, metadata: { email: resource_params[:email] })
    end
  end

  def update
    super do |resource|
      if resource.errors.empty?
        log_audit(:password_reset_completed, user: resource)
      else
        log_audit(:password_reset_failed, user: nil, metadata: { errors: resource.errors.full_messages })
      end
    end
  end
end
