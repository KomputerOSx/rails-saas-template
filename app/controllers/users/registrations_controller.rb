class Users::RegistrationsController < Devise::RegistrationsController
  def cancel_email_change
    current_user.update_columns(
      unconfirmed_email: nil,
      confirmation_token: nil,
      confirmation_sent_at: nil
    )

    flash[:toast] = { message: "Email change cancelled.", type: "success" }
    redirect_to edit_user_registration_path
  end
end
