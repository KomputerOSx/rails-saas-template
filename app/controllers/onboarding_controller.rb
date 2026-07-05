class OnboardingController < ApplicationController
  layout "onboarding"

  skip_before_action :enforce_onboarding_gate!

  def show
    return redirect_to dashboard_path if current_user.onboarding_completed?

    pointer = current_user.onboarding_current_step
    requested_key = params[:step].presence
    target = requested_key ? Onboarding.find(requested_key) : pointer

    # Can't jump ahead of the furthest step reached; revisiting an earlier step is fine.
    if target.nil? || Onboarding.index_of(target.key) > Onboarding.index_of(pointer.key)
      return redirect_to onboarding_step_path(pointer.key)
    end

    @step = target
  end

  def update
    return redirect_to dashboard_path if current_user.onboarding_completed?

    step = Onboarding.find(params[:step])
    return redirect_to onboarding_path if step.nil?

    if Onboarding.last_step?(step.key)
      # update_columns (not update!) — avoids re-running full User validations, which would
      # fail for OAuth-created users whose password_digest is blank.
      current_user.update_columns(onboarding_completed_at: Time.current, onboarding_step: step.key)
      redirect_to dashboard_path, notice: "You're all set! Welcome aboard."
    else
      next_step = Onboarding.step_after(step.key)
      pointer = current_user.onboarding_current_step
      # Only move the pointer forward — re-submitting an earlier step via Back
      # shouldn't erase progress already made further ahead.
      current_user.update_columns(onboarding_step: next_step.key) if Onboarding.index_of(next_step.key) > Onboarding.index_of(pointer.key)
      redirect_to onboarding_step_path(next_step.key)
    end
  end

  def skip
    current_user.update_columns(onboarding_completed_at: Time.current) unless current_user.onboarding_completed?
    redirect_to dashboard_path, notice: "Onboarding skipped — you can pick it up later from your account if needed."
  end
end
