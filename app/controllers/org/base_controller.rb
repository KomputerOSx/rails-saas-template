module Org
  class BaseController < ApplicationController
    before_action :require_current_organization!

    private

    def require_current_organization!
      redirect_to dashboard_path, alert: "No organization selected." unless Current.organization
    end
  end
end
