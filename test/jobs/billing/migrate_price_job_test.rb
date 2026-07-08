require "test_helper"

class Billing::MigratePriceJobTest < ActiveJob::TestCase
  setup do
    @admin = users(:one)
  end

  def stub_schedule(&block)
    period_end = 20.days.from_now.to_i
    phase_item = Struct.new(:price, :quantity).new("price_fake_starter_usd", 1)
    phase = Struct.new(:items, :start_date, :end_date).new([ phase_item ], 10.days.ago.to_i, period_end)
    fake_schedule = Struct.new(:id, :phases).new("sub_sched_test123", [ phase ])

    Stripe::SubscriptionSchedule.stub(:create, fake_schedule) do
      Stripe::SubscriptionSchedule.stub(:update, fake_schedule) do
        block.call
      end
    end
  end

  test "schedules the migration for every eligible organization on the old price" do
    organization = Organization.create_personal_for!(@admin)
    customer = organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    with_active_subscription(organization, Billing::Plans::STARTER) do
      stub_schedule do
        Billing::MigratePriceJob.perform_now(
          plan_key: "starter", currency: "usd", old_price_id: "price_fake_starter_usd",
          new_price_id: "price_new_starter_usd", new_price_cents: 1500, initiated_by_user_id: @admin.id
        )
      end
    end

    organization.reload
    assert_equal 1500, organization.pending_price_cents
    assert AuditLog.exists?(event_type: :price_migration_scheduled, resource_type: "Organization", resource_id: organization.id, user_id: @admin.id)
  end

  test "skips a grandfathered organization" do
    organization = Organization.create_personal_for!(@admin)
    organization.grandfather!
    customer = organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    with_active_subscription(organization, Billing::Plans::STARTER) do
      stub_schedule do
        Billing::MigratePriceJob.perform_now(
          plan_key: "starter", currency: "usd", old_price_id: "price_fake_starter_usd",
          new_price_id: "price_new_starter_usd", new_price_cents: 1500, initiated_by_user_id: @admin.id
        )
      end
    end

    assert_nil organization.reload.pending_price_cents
    assert_not AuditLog.exists?(event_type: :price_migration_scheduled, resource_type: "Organization", resource_id: organization.id)
  end

  test "skips an organization that already has a downgrade pending" do
    organization = Organization.create_personal_for!(@admin)
    organization.update!(pending_plan_key: "starter", pending_plan_change_at: 20.days.from_now,
      stripe_subscription_schedule_id: "sub_sched_other123")
    customer = organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    with_active_subscription(organization, Billing::Plans::STARTER) do
      stub_schedule do
        Billing::MigratePriceJob.perform_now(
          plan_key: "starter", currency: "usd", old_price_id: "price_fake_starter_usd",
          new_price_id: "price_new_starter_usd", new_price_cents: 1500, initiated_by_user_id: @admin.id
        )
      end
    end

    assert_equal "starter", organization.reload.pending_plan_key
    assert_nil organization.pending_price_cents
  end

  test "one organization's Stripe error doesn't stop the batch" do
    failing_org = Organization.create_personal_for!(@admin)
    ok_org = Organization.create_personal_for!(users(:two))
    [ failing_org, ok_org ].each do |organization|
      customer = organization.set_payment_processor(:fake_processor, allow_fake: true)
      customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")
    end

    call_count = 0
    with_active_subscription(failing_org, Billing::Plans::STARTER) do
      with_active_subscription(ok_org, Billing::Plans::STARTER) do
        Stripe::SubscriptionSchedule.stub(:create, ->(*) {
          call_count += 1
          raise Stripe::StripeError, "boom" if call_count == 1
          period_end = 20.days.from_now.to_i
          phase_item = Struct.new(:price, :quantity).new("price_fake_starter_usd", 1)
          phase = Struct.new(:items, :start_date, :end_date).new([ phase_item ], 10.days.ago.to_i, period_end)
          Struct.new(:id, :phases).new("sub_sched_test123", [ phase ])
        }) do
          Stripe::SubscriptionSchedule.stub(:update, ->(id, params) { Struct.new(:id).new(id) }) do
            Billing::MigratePriceJob.perform_now(
              plan_key: "starter", currency: "usd", old_price_id: "price_fake_starter_usd",
              new_price_id: "price_new_starter_usd", new_price_cents: 1500, initiated_by_user_id: @admin.id
            )
          end
        end
      end
    end

    assert_equal 2, call_count
  end
end
