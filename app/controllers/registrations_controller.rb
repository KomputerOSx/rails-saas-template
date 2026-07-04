class RegistrationsController < ApplicationController
  layout "auth"

  allow_unauthenticated_access only: [ :new, :create ]

  def new
    redirect_to dashboard_path and return if authenticated?

    @user = User.new
  end

  def create
    redirect_to dashboard_path and return if authenticated?

    @user = User.new(registration_params)
    @user.role = "user"

    # Validate only — no `users` row is created until the confirmation code is entered,
    # so an abandoned signup never blocks the email from being used again.
    if @user.valid?
      code = PendingRegistration.create!(email: @user.email, password_digest: @user.password_digest)
      ConfirmationMailer.confirmation_code(@user.email, code).deliver_later
      session[:pending_confirmation_email] = @user.email

      flash[:toast] = { message: "Almost there! Enter the code we emailed you to finish creating your account.", type: "success" }
      redirect_to new_confirmation_path
    else
      flash.now[:toast] = { message: @user.errors.full_messages.join(", "), type: "error" }
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end
end
