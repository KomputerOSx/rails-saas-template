class InvitationsController < ApplicationController
  include InvitationResumption

  allow_unauthenticated_access only: [ :show, :accept ]

  before_action :set_invitation

  def show
    return handle_invalid unless @invitation

    if authenticated?
      unless emails_match?
        flash.now[:alert] = "This invitation was sent to #{@invitation.email}. Log out and log in with that email to accept it."
        render :mismatched_account
      end
      # renders :show - a confirm/accept button posting to accept_invitation_path
    else
      session[:pending_invitation_token] = params[:token]

      if User.exists?(email: @invitation.email)
        redirect_to login_path, notice: "Log in to accept your invitation to join #{@invitation.organization.name}."
      else
        redirect_to new_registration_path(email: @invitation.email), notice: "Create your account to join #{@invitation.organization.name}."
      end
    end
  end

  def accept
    return handle_invalid unless @invitation

    unless authenticated? && emails_match?
      redirect_to invitation_path(params[:token])
      return
    end

    @invitation.accept!(current_user)
    log_audit(:organization_invitation_accepted, resource: @invitation.organization,
      metadata: { invitation_id: @invitation.id, role: @invitation.role.name })

    flash[:toast] = { message: "You've joined #{@invitation.organization.name}.", type: "success" }
    redirect_to dashboard_path
  end

  private

  def set_invitation
    @invitation = OrganizationInvitation.find_usable(params[:token])
  end

  def emails_match?
    @invitation.email.casecmp?(current_user.email)
  end

  def handle_invalid
    flash[:toast] = { message: "This invitation is invalid, expired, or already used.", type: "error" }
    redirect_to(authenticated? ? dashboard_path : login_path)
  end
end
