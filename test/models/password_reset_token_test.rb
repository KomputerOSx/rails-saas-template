require "test_helper"

class PasswordResetTokenTest < ActiveSupport::TestCase
  test "generate_for! returns a usable record and the raw token digests correctly" do
    record, raw_token = PasswordResetToken.generate_for!(users(:one), request_ip: "1.2.3.4", request_user_agent: "RSpec")

    assert record.persisted?
    assert_equal PasswordResetToken.digest(raw_token), record.token_digest
    assert record.usable?
    assert_equal users(:one).password_digest, record.password_digest_snapshot
  end

  test "generate_for! invalidates any previously active tokens for the same user" do
    _first, first_raw = PasswordResetToken.generate_for!(users(:one), request_ip: "1.1.1.1", request_user_agent: "A")
    _second, second_raw = PasswordResetToken.generate_for!(users(:one), request_ip: "2.2.2.2", request_user_agent: "B")

    assert_not PasswordResetToken.find_usable(first_raw)&.usable?
    assert PasswordResetToken.find_usable(second_raw).usable?
  end

  test "find_usable returns nil for a blank, unknown, expired, or used token" do
    assert_nil PasswordResetToken.find_usable(nil)
    assert_nil PasswordResetToken.find_usable("")
    assert_nil PasswordResetToken.find_usable("not-a-real-token")

    record, raw_token = PasswordResetToken.generate_for!(users(:one), request_ip: "1.2.3.4", request_user_agent: "RSpec")
    record.update!(expires_at: 1.minute.ago)
    assert_nil PasswordResetToken.find_usable(raw_token)

    record.update!(expires_at: 10.minutes.from_now, used_at: Time.current)
    assert_nil PasswordResetToken.find_usable(raw_token)
  end

  test "usable? is false once the user's password changed since the token was issued" do
    record, raw_token = PasswordResetToken.generate_for!(users(:one), request_ip: "1.2.3.4", request_user_agent: "RSpec")

    users(:one).update!(password: "Xk92!vTqZmR7")

    assert_not record.reload.usable?
    # find_usable itself only checks used_at/expires_at - it's the caller's job (see
    # PasswordResetsController#usable_token_for) to also check #usable? for the
    # password-changed-elsewhere case.
    assert_equal record, PasswordResetToken.find_usable(raw_token)
    assert_not PasswordResetToken.find_usable(raw_token).usable?
  end

  test "consume! marks the token as used" do
    record, _raw_token = PasswordResetToken.generate_for!(users(:one), request_ip: "1.2.3.4", request_user_agent: "RSpec")

    record.consume!

    assert record.used_at.present?
    assert_not record.usable?
  end

  test "digest is deterministic for the same raw token" do
    assert_equal PasswordResetToken.digest("abc123"), PasswordResetToken.digest("abc123")
    assert_not_equal PasswordResetToken.digest("abc123"), PasswordResetToken.digest("xyz789")
  end
end
