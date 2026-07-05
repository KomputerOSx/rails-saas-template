module OnboardingGate
  extend ActiveSupport::Concern

  included do
    before_action :enforce_onboarding_gate!
  end

  private

  def enforce_onboarding_gate!
    return unless current_user
    return if controller_path.start_with?("admin/")
    return if current_user.onboarding_completed?

    redirect_to onboarding_path
  end
end
