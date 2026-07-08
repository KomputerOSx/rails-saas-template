require "test_helper"

class Billing::ReconcileOrganizationJobTest < ActiveJob::TestCase
  setup do
    @organization = Organization.create_personal_for!(users(:one))
  end

  test "flags the organization as over its member limit once seats exceed the plan" do
    # Two more members than Free's 1-seat limit allows, without going through the
    # guarded invite flow (this simulates a downgrade leaving the org oversubscribed).
    @organization.memberships.create!(user: users(:two))

    assert_changes -> { @organization.reload.over_member_limit_at }, from: nil do
      Billing::ReconcileOrganizationJob.perform_now(@organization.id)
    end
    assert @organization.over_member_limit?
    assert AuditLog.exists?(event_type: :subscription_updated, resource_type: "Organization", resource_id: @organization.id)
  end

  test "clears the over-limit flag once seats are back within the plan" do
    @organization.update!(over_member_limit_at: 1.day.ago)

    Billing::ReconcileOrganizationJob.perform_now(@organization.id)

    assert_nil @organization.reload.over_member_limit_at
  end

  test "uses the given audit_event_type" do
    Billing::ReconcileOrganizationJob.perform_now(@organization.id, audit_event_type: "subscription_created")

    assert AuditLog.exists?(event_type: :subscription_created, resource_id: @organization.id)
  end

  test "does nothing for a deleted organization" do
    assert_no_difference "AuditLog.count" do
      Billing::ReconcileOrganizationJob.perform_now(-1)
    end
  end

  test "clears a pending downgrade once the subscription is on the pending plan's price" do
    @organization.update!(pending_plan_key: "starter", pending_plan_change_at: 1.day.ago,
      stripe_subscription_schedule_id: "sub_sched_test123")

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      Billing::ReconcileOrganizationJob.perform_now(@organization.id)
    end

    @organization.reload
    assert_nil @organization.pending_plan_key
    assert_nil @organization.pending_plan_change_at
    assert_nil @organization.stripe_subscription_schedule_id
  end

  test "keeps the pending downgrade while the subscription is still on the old plan" do
    @organization.update!(pending_plan_key: "starter", pending_plan_change_at: 20.days.from_now,
      stripe_subscription_schedule_id: "sub_sched_test123")

    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      Billing::ReconcileOrganizationJob.perform_now(@organization.id)
    end

    assert_equal "starter", @organization.reload.pending_plan_key
  end

  test "clears a pending downgrade when there's no active subscription anymore" do
    @organization.update!(pending_plan_key: "starter", pending_plan_change_at: 20.days.from_now,
      stripe_subscription_schedule_id: "sub_sched_test123")

    Billing::ReconcileOrganizationJob.perform_now(@organization.id)

    assert_nil @organization.reload.pending_plan_key
  end

  test "flags an active subscription on an unrecognized Stripe price in the audit metadata" do
    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.subscribe(plan: "price_unknown_custom_123")

    Billing::ReconcileOrganizationJob.perform_now(@organization.id)

    audit_log = AuditLog.where(resource_type: "Organization", resource_id: @organization.id).last
    assert_equal "price_unknown_custom_123", audit_log.metadata["unrecognized_price"]
  end
end
