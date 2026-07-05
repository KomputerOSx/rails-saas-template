module Org
  class SwitchesController < ApplicationController
    def create
      organization = current_user.organizations.find_by(id: params[:organization_id])

      if organization
        session[:current_organization_id] = organization.id
        redirect_back fallback_location: dashboard_path, notice: "Switched to #{organization.name}."
      else
        redirect_back fallback_location: dashboard_path, alert: "You don't have access to that organization."
      end
    end
  end
end
