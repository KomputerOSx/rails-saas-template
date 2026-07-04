class Users::RegistrationsController < Devise::RegistrationsController
  def create
    super do |resource|
      log_audit(:user_registered, user: resource, metadata: { email: resource.email }) if resource.persisted?
    end
  end

  def update
    prev_unconfirmed_email = resource.unconfirmed_email if resource.respond_to?(:unconfirmed_email)

    super do |resource|
      if resource.errors.empty?
        log_audit(:password_change, user: resource) if resource.saved_change_to_encrypted_password?

        if resource.unconfirmed_email.present? && resource.unconfirmed_email != prev_unconfirmed_email
          log_audit(:email_change_requested, user: resource, metadata: { new_email: resource.unconfirmed_email })
          flash[:toast] = { message: "Please check your new email address to confirm the change.", type: "success" }
        end
      end
    end
  end

  def destroy
    log_audit(:user_deleted, user: nil, metadata: { deleted_user_id: current_user.id, email: current_user.email })
    super
  end

  def cancel_email_change
    log_audit(:email_change_cancelled)

    current_user.update_columns(
      unconfirmed_email: nil,
      confirmation_token: nil,
      confirmation_sent_at: nil
    )

    flash[:toast] = { message: "Email change cancelled.", type: "success" }
    redirect_to edit_user_registration_path
  end

  protected

  def after_sign_up_path_for(resource)
    new_user_registration_path
  end

  def after_inactive_sign_up_path_for(resource)
    new_user_registration_path
  end

  def after_update_path_for(resource)
    edit_user_registration_path
  end
end
