require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "fresh-user@example.com", password: "Xk92!vTqZmR7", confirmed_at: Time.current)
    post login_path, params: { email: @user.email, password: "Xk92!vTqZmR7" }
  end

  test "show defaults to the first step for a brand-new user" do
    get onboarding_path
    assert_response :success
  end

  test "show redirects an already-onboarded user straight to the dashboard" do
    @user.update_columns(onboarding_completed_at: Time.current)

    get onboarding_path

    assert_redirected_to dashboard_path
  end

  test "show won't let a user jump ahead of the furthest step they've reached" do
    get onboarding_step_path("team")

    assert_redirected_to onboarding_step_path("welcome")
  end

  test "show allows revisiting an earlier step once further progress has been made" do
    @user.update_columns(onboarding_step: "team")

    get onboarding_step_path("welcome")

    assert_response :success
  end

  test "update advances the pointer to the next step" do
    patch onboarding_step_path("welcome")

    assert_redirected_to onboarding_step_path("profile")
    assert_equal "profile", @user.reload.onboarding_step
  end

  test "update on the last step completes onboarding" do
    @user.update_columns(onboarding_step: "finish")

    patch onboarding_step_path("finish")

    assert_redirected_to dashboard_path
    assert @user.reload.onboarding_completed?
  end

  test "update does not rewind progress when resubmitting an earlier step" do
    @user.update_columns(onboarding_step: "team")

    patch onboarding_step_path("welcome")

    assert_equal "team", @user.reload.onboarding_step
  end

  test "skip marks onboarding complete without requiring any steps" do
    post skip_onboarding_path

    assert_redirected_to dashboard_path
    assert @user.reload.onboarding_completed?
  end
end
