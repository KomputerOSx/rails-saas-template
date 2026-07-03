class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  layout :determine_layout

  private

  def determine_layout
    if user_signed_in?
      "application"
    else
      devise_controller? ? "auth" : "application"
    end
  end

  def after_sign_in_path_for(resource)
    dashboard_path
  end
end
