require "test_helper"

class PasswordResetsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "new renders the forgot-password form" do
    get new_password_reset_path
    assert_response :success
  end

  test "create sends a reset link for an existing, confirmed, unlocked account" do
    assert_enqueued_emails 1 do
      post password_resets_path, params: { email: users(:one).email }
    end

    assert_redirected_to new_password_reset_path
    assert PasswordResetToken.exists?(user: users(:one))
  end

  test "create gives the same generic response for a non-existent email, to avoid enumeration" do
    assert_no_enqueued_emails do
      post password_resets_path, params: { email: "nobody@example.com" }
    end

    assert_redirected_to new_password_reset_path
    assert_equal "If that account exists, a password reset link has been sent.", flash[:notice]
  end

  test "create does not send a reset link for an unconfirmed account" do
    unconfirmed = User.create!(email: "unconfirmed@example.com", password: "Xk92!vTqZmR7", confirmed_at: nil)

    assert_no_enqueued_emails do
      post password_resets_path, params: { email: unconfirmed.email }
    end

    assert_redirected_to new_password_reset_path
  end

  test "edit rejects an invalid or expired token" do
    get edit_password_reset_path(token: "not-a-real-token")
    assert_redirected_to new_password_reset_path
    assert_equal "This password reset link is invalid or has expired.", flash[:alert]
  end

  test "edit accepts a valid token" do
    _record, raw_token = PasswordResetToken.generate_for!(users(:one), request_ip: "1.2.3.4", request_user_agent: "RSpec")

    get edit_password_reset_path(token: raw_token)

    assert_response :success
  end

  test "update resets the password, destroys sessions, and consumes the token" do
    _record, raw_token = PasswordResetToken.generate_for!(users(:one), request_ip: "1.2.3.4", request_user_agent: "RSpec")
    other_session = users(:one).sessions.create!

    patch password_reset_path(token: raw_token), params: {
      password: "Xk92!vTqZmR7",
      password_confirmation: "Xk92!vTqZmR7"
    }

    assert_redirected_to login_path
    assert users(:one).reload.authenticate("Xk92!vTqZmR7")
    assert_not Session.exists?(other_session.id)
    assert_not PasswordResetToken.find_usable(raw_token)
  end

  test "update rejects an invalid token" do
    patch password_reset_path(token: "not-a-real-token"), params: {
      password: "Xk92!vTqZmR7",
      password_confirmation: "Xk92!vTqZmR7"
    }

    assert_redirected_to new_password_reset_path
  end

  test "update rerenders on a mismatched confirmation" do
    _record, raw_token = PasswordResetToken.generate_for!(users(:one), request_ip: "1.2.3.4", request_user_agent: "RSpec")

    patch password_reset_path(token: raw_token), params: {
      password: "Xk92!vTqZmR7",
      password_confirmation: "SomethingDifferent1!"
    }

    assert_response :unprocessable_entity
    assert users(:one).reload.authenticate("password123")
  end

  test "update rejects a reset link for a currently-locked account" do
    users(:one).update!(failed_login_attempts: 5, locked_until: 1.hour.from_now)
    _record, raw_token = PasswordResetToken.generate_for!(users(:one), request_ip: "1.2.3.4", request_user_agent: "RSpec")

    patch password_reset_path(token: raw_token), params: {
      password: "Xk92!vTqZmR7",
      password_confirmation: "Xk92!vTqZmR7"
    }

    assert_redirected_to new_password_reset_path
    assert users(:one).reload.locked?
  end
end
