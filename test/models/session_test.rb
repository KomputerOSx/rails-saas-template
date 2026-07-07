require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "before_create stamps user_agent/ip_address from Current and sets an expiry" do
    Current.user_agent = "RSpec Agent"
    Current.ip_address = "9.9.9.9"

    session = users(:one).sessions.create!

    assert_equal "RSpec Agent", session.user_agent
    assert_equal "9.9.9.9", session.ip_address
    assert_in_delta Session::SESSION_DURATION.from_now, session.expires_at, 2.seconds
  ensure
    Current.reset
  end

  # before_create unconditionally overwrites expires_at with SESSION_DURATION.from_now,
  # so tests that need a specific expiry set it via update! after creation.

  test "expired? reflects whether expires_at has passed" do
    fresh = users(:one).sessions.create!
    stale = users(:one).sessions.create!.tap { |s| s.update!(expires_at: 1.hour.ago) }

    assert_not fresh.expired?
    assert stale.expired?
  end

  test "time_remaining is 0 once expired, otherwise minutes until expiry" do
    session = users(:one).sessions.create!.tap { |s| s.update!(expires_at: 30.minutes.from_now) }
    assert_in_delta 30, session.time_remaining, 1

    session.update!(expires_at: 1.hour.ago)
    assert_equal 0, session.time_remaining
  end

  test "active and expired scopes partition sessions by expiry" do
    fresh = users(:one).sessions.create!
    stale = users(:one).sessions.create!.tap { |s| s.update!(expires_at: 1.hour.ago) }

    assert_includes Session.active, fresh
    assert_not_includes Session.active, stale
    assert_includes Session.expired, stale
    assert_not_includes Session.expired, fresh
  end

  test "cleanup_expired! destroys only expired sessions" do
    fresh = users(:one).sessions.create!
    stale = users(:one).sessions.create!.tap { |s| s.update!(expires_at: 1.hour.ago) }

    Session.cleanup_expired!

    assert Session.exists?(fresh.id)
    assert_not Session.exists?(stale.id)
  end
end
