require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  test "recent orders newest first" do
    older = AuditLog.create!(event_type: :login_success, created_at: 2.days.ago)
    newer = AuditLog.create!(event_type: :login_success, created_at: 1.hour.ago)

    assert_equal [ newer, older ], AuditLog.recent.where(id: [ older.id, newer.id ]).to_a
  end

  test "for_user scopes to a single user's logs" do
    mine = AuditLog.create!(event_type: :login_success, user: users(:one))
    theirs = AuditLog.create!(event_type: :login_success, user: users(:two))

    scoped = AuditLog.for_user(users(:one))
    assert_includes scoped, mine
    assert_not_includes scoped, theirs
  end

  test "for_resource scopes to a resource type and id" do
    organization = Organization.create!(name: "Acme", slug: "acme")
    matching = AuditLog.create!(event_type: :organization_created, resource_type: "Organization", resource_id: organization.id)
    other = AuditLog.create!(event_type: :organization_created, resource_type: "Organization", resource_id: organization.id + 1)

    scoped = AuditLog.for_resource("Organization", organization.id)
    assert_includes scoped, matching
    assert_not_includes scoped, other
  end

  test "security_events only includes the designated sensitive event types" do
    security_event = AuditLog.create!(event_type: :account_locked)
    benign_event = AuditLog.create!(event_type: :login_success)

    scoped = AuditLog.security_events
    assert_includes scoped, security_event
    assert_not_includes scoped, benign_event
  end

  test "metadata round-trips through JSON serialization" do
    log = AuditLog.create!(event_type: :user_updated, metadata: { changes: { "email" => [ "a@x.com", "b@x.com" ] } })

    assert_equal({ "changes" => { "email" => [ "a@x.com", "b@x.com" ] } }, log.reload.metadata)
  end
end
