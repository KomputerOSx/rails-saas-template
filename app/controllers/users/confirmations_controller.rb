class Users::ConfirmationsController < Devise::ConfirmationsController
  def show
    super do |resource|
      if resource.errors.empty?
        event = resource.saved_change_to_email? ? :email_change_confirmed : :account_confirmed
        log_audit(event, user: resource, metadata: { email: resource.email })

        if event == :email_change_confirmed
          flash[:toast] = { message: "Email address updated successfully.", type: "success" }
        end
      end
    end
  end
end
