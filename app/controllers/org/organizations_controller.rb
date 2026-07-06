module Org
  class OrganizationsController < BaseController
    def update
      authorize Current.organization

      if Current.organization.update(organization_params)
        log_audit(:organization_updated, resource: Current.organization)
        redirect_to org_settings_path, notice: "Organization updated."
      else
        @memberships = Current.organization.memberships.includes(:user, :roles)
        @pending_invitations = Current.organization.organization_invitations.outstanding.includes(:role, :invited_by)
        render "org/settings/index", status: :unprocessable_entity
      end
    end

    private

    def organization_params
      params.require(:organization).permit(:name)
    end
  end
end
