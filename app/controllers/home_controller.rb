class HomeController < ApplicationController
  layout "landing"

  allow_unauthenticated_access

  def index
    redirect_to dashboard_path if authenticated?
  end
end
