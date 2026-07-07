class ApplicationController < ActionController::Base
  include Authentication
  include MaintenanceGate
  include OnboardingGate
  include Pundit::Authorization
  include AuditLogging
  include CurrentOrganization

  protect_from_forgery with: :exception

  rescue_from Pundit::NotAuthorizedError, with: :deny_authorization!

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  layout "application"

  private

  # The boxed OTP inputs (two-factor Stimulus controller) submit one digit per
  # `code[]` field - this joins them back into the single code string the rest
  # of the app's verification methods expect.
  def otp_code_param
    Array(params[:code]).join
  end

  def deny_authorization!
    log_audit(:authorization_denied, metadata: { path: request.path })
    redirect_to root_path, alert: "You are not authorized to access this page."
  end
end
