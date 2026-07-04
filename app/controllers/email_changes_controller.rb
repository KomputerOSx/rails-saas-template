class EmailChangesController < ApplicationController
  layout false

  def new
    render partial: "frame"
  end

  def create
    code = current_user.request_email_change!(params[:email])

    if code
      EmailChangeMailer.confirm_old_email(current_user, code).deliver_later
      log_audit(:email_change_requested, metadata: { old_email: current_user.email, new_email: current_user.unconfirmed_email })
      render partial: "frame"
    else
      render partial: "new_email_form", status: :unprocessable_entity
    end
  end

  def confirm_old
    result = current_user.confirm_email_change_old!(otp_code_param)

    case result
    when :expired, :locked
      current_user.cancel_email_change!
      log_audit(:email_change_cancelled, metadata: { reason: result.to_s })
      current_user.errors.add(:base, result == :expired ? "This code has expired. Please start again." : "Too many incorrect attempts. Please start again.")
      render partial: "new_email_form", status: :unprocessable_entity
    when :invalid
      current_user.errors.add(:code, "is incorrect. Please try again.")
      render partial: "verify_old_form", status: :unprocessable_entity
    else
      # result is the freshly generated code for the new address
      EmailChangeMailer.confirm_new_email(current_user, result).deliver_later
      log_audit(:email_change_confirmed_old, metadata: { old_email: current_user.email })
      render partial: "frame"
    end
  end

  def confirm_new
    result = current_user.confirm_email_change_new!(otp_code_param)

    case result
    when :expired, :locked
      current_user.cancel_email_change!
      log_audit(:email_change_cancelled, metadata: { reason: result.to_s })
      current_user.errors.add(:base, result == :expired ? "This code has expired. Please start again." : "Too many incorrect attempts. Please start again.")
      render partial: "new_email_form", status: :unprocessable_entity
    when :invalid
      current_user.errors.add(:code, "is incorrect. Please try again.")
      render partial: "verify_new_form", status: :unprocessable_entity
    when :completed
      log_audit(:email_change_completed, metadata: { email: current_user.email })
      flash[:toast] = { message: "Email address updated successfully!", type: "success" }
      render partial: "success"
    end
  end

  def destroy
    current_user.cancel_email_change!
    log_audit(:email_change_cancelled, metadata: { reason: "user_cancelled" })
    flash[:toast] = { message: "Email change cancelled.", type: "success" }
    redirect_to profile_path
  end
end
