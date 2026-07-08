module Admin
  # Toggles whether an organization is permanently excluded from Billing::MigratePriceJob -
  # see Organization#grandfather!/#ungrandfather!. Typically reached from the price-migration
  # preview page so an admin can pull specific customers out before running a migration, but
  # not tied to any particular migration - it's a durable account attribute.
  class OrganizationGrandfathersController < BaseController
    before_action { authorize :system, :manage_billing?, policy_class: SystemPolicy }

    def create
      organization = Organization.find(params[:organization_id])
      organization.grandfather!
      log_audit(:organization_grandfathered, resource: organization)
      redirect_back fallback_location: new_admin_price_migration_path, notice: "#{organization.name} is now grandfathered on its current price."
    end

    def destroy
      organization = Organization.find(params[:organization_id])
      organization.ungrandfather!
      log_audit(:organization_ungrandfathered, resource: organization)
      redirect_back fallback_location: new_admin_price_migration_path, notice: "#{organization.name} is no longer grandfathered."
    end
  end
end
