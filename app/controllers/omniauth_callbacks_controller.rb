class OmniauthCallbacksController < ApplicationController
  include InvitationResumption
  include TwoFactorAuthentication
  include LoginCompletable

  layout "auth"

  allow_unauthenticated_access
  skip_before_action :enforce_maintenance_mode!

  def create
    auth = request.env["omniauth.auth"]
    user = find_or_create_user_from(auth)

    if user.nil?
      redirect_to login_path, alert: "We couldn't get an email address from #{auth.provider.to_s.titleize}. Please sign up with email and password instead."
      return
    end

    if user.locked? || user.disabled?
      log_audit(:login_failure, user: user, metadata: { provider: auth.provider, reason: user.disabled? ? "account_disabled" : "account_locked" })
      redirect_to login_path, alert: "This account is locked. Please try again later or reset your password."
      return
    end

    if user.totp_enabled? && !trusted_two_factor_device?(user)
      begin_two_factor_for(user)
      redirect_to two_factor_login_path, notice: "Enter the code from your authenticator app."
    else
      complete_login_for(user, skipped_two_factor: true)
    end
  end

  def failure
    log_audit(:login_failure, user: nil, metadata: { reason: "omniauth_failure", message: params[:message] })
    redirect_to login_path, alert: "Authentication failed. Please try again or use your email and password."
  end

  private

  # Looks up an existing linked identity first. Otherwise falls back to matching
  # by email — safe because the provider has already verified ownership of that
  # address — and links a new identity to that account. If neither matches,
  # provisions a brand-new user exactly like ConfirmationsController#create does
  # (personal organization + owner role), except confirmation is skipped since
  # the provider already vouches for the email.
  def find_or_create_user_from(auth)
    identity = Identity.find_by(provider: auth.provider, uid: auth.uid)
    return identity.user if identity

    email = auth.info.email.to_s.strip.downcase
    return nil if email.blank?

    ActiveRecord::Base.transaction do
      user = User.find_by(email: email)

      if user
        user.update!(confirmed_at: Time.current) unless user.confirmed?
      else
        user = User.new(email: email, confirmed_at: Time.current)
        user.save!(validate: false)
        organization = Organization.create_personal_for!(user)
        log_audit(:user_registered, user: user, metadata: { email: user.email, provider: auth.provider })
        log_audit(:account_confirmed, user: user, metadata: { email: user.email, provider: auth.provider })
        log_audit(:organization_created, user: user, resource: organization, metadata: { name: organization.name, slug: organization.slug })
        log_audit(:membership_created, user: user, resource: organization)
      end

      user.identities.create!(provider: auth.provider, uid: auth.uid, email: email)
      user
    end
  end
end
