module Billing
  # Bulk half of a price migration - triggered by Admin::PriceMigrationsController#create.
  # Finds every active subscription still on `old_price_id` and schedules each owning
  # organization onto `new_price_id` at its own next renewal (Organization#schedule_price_migration!),
  # skipping grandfathered organizations and any that already have a downgrade pending rather
  # than silently overriding either. One organization's failure doesn't stop the batch.
  class MigratePriceJob < ApplicationJob
    queue_as :default

    def perform(plan_key:, currency:, old_price_id:, new_price_id:, new_price_cents:, initiated_by_user_id:)
      Organization.on_stripe_price(old_price_id).each do |organization|
        next if organization.grandfathered?
        next if organization.pending_plan_key.present?

        begin
          organization.schedule_price_migration!(new_price_id: new_price_id, new_price_cents: new_price_cents)
          AuditLog.create!(
            event_type: :price_migration_scheduled,
            user_id: initiated_by_user_id,
            resource_type: "Organization",
            resource_id: organization.id,
            metadata: { plan: plan_key, currency: currency, old_price_id: old_price_id, new_price_id: new_price_id }
          )
        rescue Pay::Stripe::Error, ArgumentError => e
          Rails.logger.error("[Billing::MigratePriceJob] failed for organization #{organization.id}: #{e.message}")
        end
      end
    end
  end
end
