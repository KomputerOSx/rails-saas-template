require "test_helper"

class TwoFactorChallengeTest < ActiveSupport::TestCase
  def build_challenge(**attrs)
    users(:one).two_factor_challenges.create!({
      challenge_id: SecureRandom.uuid,
      delivery_method: "email",
      expires_at: 10.minutes.from_now
    }.merge(attrs))
  end

  test "expired? reflects whether expires_at has passed" do
    fresh = build_challenge(expires_at: 10.minutes.from_now)
    stale = build_challenge(expires_at: 1.minute.ago)

    assert_not fresh.expired?
    assert stale.expired?
  end

  test "active? is true only when unused and not expired" do
    fresh = build_challenge(expires_at: 10.minutes.from_now)
    assert fresh.active?

    expired = build_challenge(expires_at: 1.minute.ago)
    assert_not expired.active?

    used = build_challenge(expires_at: 10.minutes.from_now, used_at: Time.current)
    assert_not used.active?
  end

  test "active scope matches active?" do
    fresh = build_challenge(expires_at: 10.minutes.from_now)
    expired = build_challenge(expires_at: 1.minute.ago)
    used = build_challenge(expires_at: 10.minutes.from_now, used_at: Time.current)

    assert_includes TwoFactorChallenge.active, fresh
    assert_not_includes TwoFactorChallenge.active, expired
    assert_not_includes TwoFactorChallenge.active, used
  end

  test "delivery_method enum accepts email and totp" do
    challenge = build_challenge(delivery_method: "totp")
    assert challenge.delivery_method_totp?
    assert_not challenge.delivery_method_email?
  end
end
