require "test_helper"

class PasswordsTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { email: users(:one).email, password: "password123" }
  end

  test "edit renders the change-password form" do
    get edit_password_path
    assert_response :success
  end

  test "update changes the password when the current password is correct" do
    patch password_path, params: {
      current_password: "password123",
      password: "Xk92!vTqZmR7",
      password_confirmation: "Xk92!vTqZmR7"
    }

    assert_redirected_to dashboard_path
    assert users(:one).reload.authenticate("Xk92!vTqZmR7")
  end

  test "update rejects an incorrect current password" do
    patch password_path, params: {
      current_password: "wrong-password",
      password: "Xk92!vTqZmR7",
      password_confirmation: "Xk92!vTqZmR7"
    }

    assert_response :unprocessable_entity
    assert users(:one).reload.authenticate("password123")
  end

  test "update rejects a mismatched confirmation" do
    patch password_path, params: {
      current_password: "password123",
      password: "Xk92!vTqZmR7",
      password_confirmation: "SomethingDifferent1!"
    }

    assert_response :unprocessable_entity
    assert users(:one).reload.authenticate("password123")
  end

  test "update destroys other sessions but keeps the current one" do
    other_session = users(:one).sessions.create!

    patch password_path, params: {
      current_password: "password123",
      password: "Xk92!vTqZmR7",
      password_confirmation: "Xk92!vTqZmR7"
    }

    assert_not Session.exists?(other_session.id)
  end
end
