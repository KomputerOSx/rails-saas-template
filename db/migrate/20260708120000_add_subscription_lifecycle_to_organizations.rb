class AddSubscriptionLifecycleToOrganizations < ActiveRecord::Migration[8.1]
  def up
    add_column :organizations, :pending_plan_key, :string
    add_column :organizations, :pending_plan_change_at, :datetime
    add_column :organizations, :stripe_subscription_schedule_id, :string
    add_column :organizations, :trial_used_at, :datetime

    # Orgs that already subscribed before trials existed shouldn't get a free trial on their
    # next (re)subscribe - they were already paying customers.
    execute <<~SQL
      UPDATE organizations
      SET trial_used_at = CURRENT_TIMESTAMP
      WHERE id IN (
        SELECT DISTINCT owner_id FROM pay_customers
        INNER JOIN pay_subscriptions ON pay_subscriptions.customer_id = pay_customers.id
        WHERE pay_customers.owner_type = 'Organization'
      )
    SQL
  end

  def down
    remove_column :organizations, :pending_plan_key
    remove_column :organizations, :pending_plan_change_at
    remove_column :organizations, :stripe_subscription_schedule_id
    remove_column :organizations, :trial_used_at
  end
end
