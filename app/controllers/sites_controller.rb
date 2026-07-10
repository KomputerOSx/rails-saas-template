# frozen_string_literal: true

class SitesController < ApplicationController
  layout "landing"

  allow_unauthenticated_access
  skip_before_action :enforce_onboarding_gate!
  skip_before_action :enforce_maintenance_mode!

  def show
    @organization = resolve_organization
    return head :not_found unless @organization

    render :show
  end

  private

  def resolve_organization
    organization_id = request.env[CustomDomainResolver::ENV_KEY]
    return Organization.find_by(id: organization_id) if organization_id

    id = Organization.find_id_by_custom_domain(request.host)
    Organization.find_by(id: id) if id
  end
end
