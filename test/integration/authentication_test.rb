require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "home page shows authentication links" do
    get root_path

    assert_response :success
    assert_select "a", text: "Login"
    assert_select "a", text: "Sign up"
    assert_select "h1", text: "Build your SaaS at warp speed"
  end

  test "user can sign up, confirm, and sign in" do
    perform_enqueued_jobs do
      post registration_path, params: {
        user: {
          email: "new@example.com",
          password: "Tr8kMvln52",
          password_confirmation: "Tr8kMvln52"
        }
      }
    end

    assert_redirected_to new_confirmation_path

    user = User.find_by(email: "new@example.com")
    assert_nil user

    code = ActionMailer::Base.deliveries.last.body.encoded[/(\d{6})/, 1]
    post confirmations_path, params: { code: code.chars }

    assert_redirected_to dashboard_path
    user = User.find_by(email: "new@example.com")
    assert user.present?
    assert user.confirmed?

    # A brand-new user hasn't completed onboarding yet, so dashboard_path itself
    # redirects to the onboarding flow.
    follow_redirect!
    assert_redirected_to onboarding_path
  end

  test "user can sign in and sign out" do
    post login_path, params: { email: users(:one).email, password: "password123" }

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select "button", text: /Logout/

    delete session_path

    assert_redirected_to root_path
    follow_redirect!
    assert_select "a", text: "Login"
  end

  test "account locks after too many failed login attempts" do
    5.times do
      post login_path, params: { email: users(:one).email, password: "wrong-password" }
    end

    assert users(:one).reload.locked?

    # Rack::Attack's own "logins/email" throttle (config/initializers/rack_attack.rb)
    # has the same limit (5 per 20 minutes) and has now also been tripped by the
    # attempts above, so it intercepts this request before the controller's own
    # account-lockout check runs - a real login attempt at this point would be
    # blocked by either layer.
    post login_path, params: { email: users(:one).email, password: "password123" }
    assert_response :too_many_requests
  end
end
