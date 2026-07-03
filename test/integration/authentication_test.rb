require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "home page shows authentication links" do
    get root_path

    assert_response :success
    assert_select "a", text: "Log in"
    assert_select "a", text: "Sign up"
    assert_select "h1", text: "Welcome to Windtunnel"
  end

  test "user can sign up and log out" do
    post user_registration_path, params: {
      user: {
        email: "new@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    assert_redirected_to root_path
    follow_redirect!
    assert_select "button", text: "Log out"

    delete destroy_user_session_path

    assert_redirected_to root_path
    follow_redirect!
    assert_select "a", text: "Log in"
  end

  test "user can log in" do
    post user_session_path, params: {
      user: {
        email: users(:one).email,
        password: "password123"
      }
    }

    assert_redirected_to root_path
    follow_redirect!
    assert_select "button", text: "Log out"
  end
end
