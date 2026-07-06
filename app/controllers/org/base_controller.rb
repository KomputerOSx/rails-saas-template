module Org
  class BaseController < ApplicationController
    before_action :require_current_organization!
    after_action :verify_authorized

    private

    def require_current_organization!
      redirect_to dashboard_path, alert: "No organization selected." unless Current.organization
    end
  end
end
