module Admin
  # Bulk-moves every active subscriber currently on `old_price_id` to whatever price
  # Billing::Plans currently resolves for that plan/currency, effective at each subscriber's own
  # next renewal (no mid-cycle charge) - see Organization#schedule_price_migration! and
  # Billing::MigratePriceJob. Grandfathered organizations, and any with a downgrade already
  # pending, are always skipped (see Admin::OrganizationGrandfathersController for the former).
  class PriceMigrationsController < BaseController
    before_action { authorize :system, :manage_billing?, policy_class: SystemPolicy }

    def new
      @plan_key = params[:plan_key].presence || Billing::Plans::STARTER.key
      @currency = params[:currency].presence || Billing::Plans::DEFAULT_CURRENCY
      @old_price_id = params[:old_price_id].to_s.strip

      @preview = build_preview if @old_price_id.present?
    end

    def create
      plan = Billing::Plans.find(params[:plan_key])
      currency = params[:currency].presence || Billing::Plans::DEFAULT_CURRENCY
      old_price_id = params[:old_price_id].to_s.strip

      if plan.nil? || plan.free? || old_price_id.blank?
        return redirect_to new_admin_price_migration_path, alert: "Choose a plan, currency, and the old Stripe price id."
      end

      new_price_id = plan.resolved_stripe_price_id(currency)
      if new_price_id.blank? || new_price_id == old_price_id
        return redirect_to new_admin_price_migration_path(plan_key: plan.key, currency: currency, old_price_id: old_price_id),
          alert: "Billing::Plans doesn't currently resolve a different price for #{plan.name}/#{currency.upcase} - " \
                 "update credentials.stripe.price_ids (and the plan's displayed cents) to the new price first."
      end

      Billing::MigratePriceJob.perform_later(
        plan_key: plan.key, currency: currency, old_price_id: old_price_id,
        new_price_id: new_price_id, new_price_cents: plan.price_cents(currency),
        initiated_by_user_id: current_user.id
      )
      log_audit(:price_migration_started, metadata: {
        plan: plan.key, currency: currency, old_price_id: old_price_id, new_price_id: new_price_id
      })

      redirect_to new_admin_price_migration_path(plan_key: plan.key, currency: currency),
        notice: "Migration started in the background - affected organizations will be scheduled to move at their own next renewal."
    end

    private

    def build_preview
      plan = Billing::Plans.find(@plan_key)
      return nil if plan.nil? || plan.free?

      organizations = Organization.on_stripe_price(@old_price_id)
      {
        plan: plan,
        new_price_id: plan.resolved_stripe_price_id(@currency),
        new_price_cents: plan.price_cents(@currency),
        eligible: organizations.reject(&:grandfathered?),
        grandfathered: organizations.select(&:grandfathered?)
      }
    end
  end
end
