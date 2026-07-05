module LoginCompletable
  extend ActiveSupport::Concern

  private

  def complete_login_for(user, skipped_two_factor: false)
    user.update(last_sign_in_at: Time.current)
    start_new_session_for(user)

    log_audit(:two_factor_success, user: user) unless skipped_two_factor
    log_audit(:login_success, user: user, metadata: { skipped_two_factor: skipped_two_factor })

    invitation = resume_pending_invitation_for(user)
    notice = invitation ? "Logged in successfully. You've joined #{invitation.organization.name}." : "Logged in successfully."
    redirect_to dashboard_path, notice: notice
  end
end
