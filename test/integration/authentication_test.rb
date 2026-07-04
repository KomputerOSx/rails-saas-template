require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "home page shows authentication links" do
    get root_path

    assert_response :success
    assert_select "a", text: "Sign in"
    assert_select "a", text: "Sign up"
    assert_select "h1", text: "Build Your SaaS App At Warp Speed"
  end

  test "user can sign up, confirm, and sign in" do
    post registration_path, params: {
      user: {
        email: "new@example.com",
        password: "Tr8kMvln52",
        password_confirmation: "Tr8kMvln52"
      }
    }

    assert_redirected_to login_path

    user = User.find_by(email: "new@example.com")
    assert user.present?
    assert_not user.confirmed?

    get confirm_email_path(token: user.confirmation_token)
    assert_redirected_to login_path
    assert user.reload.confirmed?

    post login_path, params: { email: user.email, password: "Tr8kMvln52" }

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select "button", text: "Sign out"
  end

  test "user can sign in and sign out" do
    post login_path, params: { email: users(:one).email, password: "password123" }

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select "button", text: "Sign out"

    delete session_path

    assert_redirected_to root_path
    follow_redirect!
    assert_select "a", text: "Sign in"
  end

  test "account locks after too many failed login attempts" do
    5.times do
      post login_path, params: { email: users(:one).email, password: "wrong-password" }
    end

    assert users(:one).reload.locked?

    post login_path, params: { email: users(:one).email, password: "password123" }
    assert_response :unprocessable_entity
  end
end
