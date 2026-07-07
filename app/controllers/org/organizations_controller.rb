module Org
  class OrganizationsController < BaseController
    def update
      authorize Current.organization

      if Current.organization.update(organization_params)
        log_audit(:organization_updated, resource: Current.organization)
        respond_to do |format|
          format.turbo_stream do
            flash.now[:toast] = { message: "Organization updated.", type: "success" }
            render turbo_stream: [
              turbo_stream.replace(dom_id(Current.organization, :editor), partial: "org/settings/name_editor"),
              turbo_stream.replace("flash_messages", partial: "shared/flash")
            ]
          end
          format.html { redirect_to org_settings_path, notice: "Organization updated." }
        end
      else
        @memberships = Current.organization.memberships.includes(:user, :roles)
        @pending_invitations = Current.organization.organization_invitations.outstanding.includes(:role, :invited_by)
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(dom_id(Current.organization, :editor), partial: "org/settings/name_editor"),
                   status: :unprocessable_entity
          end
          format.html { render "org/settings/index", status: :unprocessable_entity }
        end
      end
    end

    private

    def organization_params
      params.require(:organization).permit(:name)
    end
  end
end
