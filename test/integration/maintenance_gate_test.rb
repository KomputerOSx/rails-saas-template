require "test_helper"

class MaintenanceGateTest < ActionDispatch::IntegrationTest
  setup { MaintenanceMode.enable!(message: "Down for scheduled maintenance.") }
  teardown { MaintenanceMode.disable! }

  test "an authenticated non-admin sees the maintenance page instead of the dashboard" do
    post login_path, params: { email: users(:one).email, password: "password123" }
    assert_redirected_to dashboard_path

    get dashboard_path

    assert_response :service_unavailable
    assert_includes @response.body, "Down for scheduled maintenance."
  end

  test "an anonymous visitor sees the maintenance page on the root path" do
    get root_path

    assert_response :service_unavailable
    assert_includes @response.body, "Down for scheduled maintenance."
  end

  test "a system admin is unaffected everywhere, including the admin namespace" do
    role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }
    users(:one).grant_role!(role)

    post login_path, params: { email: users(:one).email, password: "password123" }
    assert_redirected_to dashboard_path

    get dashboard_path
    assert_response :success

    get admin_root_path
    assert_response :success
  end

  test "the login page and sign-in flow remain reachable during maintenance" do
    get login_path
    assert_response :success

    post login_path, params: { email: users(:one).email, password: "password123" }
    assert_redirected_to dashboard_path
  end
end
