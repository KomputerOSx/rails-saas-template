require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  test "a user can sign in and sign out through the real UI" do
    visit login_path

    fill_in "email", with: users(:one).email
    fill_in "password", with: "password123"
    click_on "Login"

    assert_selector "h1", text: "Dashboard"

    find("[aria-label='Account menu']", match: :first).click
    click_on "Logout"

    assert_selector "a", text: "Login"
  end
end
