class EmailPreferencesController < ApplicationController
  layout "auth"

  allow_unauthenticated_access only: [ :show, :update, :one_click ]

  # RFC 8058: mail providers' servers POST here directly with no CSRF token or cookies at all -
  # without this exemption every one-click unsubscribe would 422.
  skip_forgery_protection only: :one_click

  before_action :set_user

  def show
    return handle_invalid unless @user

    @highlighted_category = EmailCampaign::OPTIONAL_CATEGORIES.find { _1 == params[:category] }
  end

  def update
    return handle_invalid unless @user

    EmailCampaign::OPTIONAL_CATEGORIES.each do |category|
      if params[:subscribed]&.key?(category)
        @user.resubscribe_to_email_category!(category)
      else
        @user.unsubscribe_from_email_category!(category)
      end
    end

    flash[:toast] = { message: "Your email preferences have been updated.", type: "success" }
    redirect_to email_preference_path(params[:token])
  end

  # RFC 8058 List-Unsubscribe-Post target - no confirmation step by design.
  def one_click
    category = EmailCampaign::OPTIONAL_CATEGORIES.find { _1 == params[:category] }
    @user.unsubscribe_from_email_category!(category) if @user && category

    head :ok
  end

  private

  def set_user
    @user = User.find_signed(params[:token], purpose: :email_unsubscribe)
  end

  def handle_invalid
    render :invalid, status: :not_found
  end
end
