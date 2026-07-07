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
end
