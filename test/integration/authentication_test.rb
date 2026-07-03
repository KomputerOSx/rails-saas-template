require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "home page shows authentication links" do
    get root_path

    assert_response :success
    assert_select "a", text: "Sign in"
    assert_select "a", text: "Sign up"
    assert_select "h1", text: "Build Your SaaS App At Warp Speed"
  end

  test "user can sign up and sign out" do
    post user_registration_path, params: {
      user: {
        email: "new@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select "button", text: "Sign out"

    delete destroy_user_session_path

    assert_redirected_to root_path
    follow_redirect!
    assert_select "a", text: "Sign in"
  end

  test "user can sign in" do
    post user_session_path, params: {
      user: {
        email: users(:one).email,
        password: "password123"
      }
    }

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select "button", text: "Sign out"
  end
end
