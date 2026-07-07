require "test_helper"

class AdminDashboardTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    system_admin_role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }
    @admin.grant_role!(system_admin_role)

    post login_path, params: { email: @admin.email, password: "password123" }
  end

  test "index renders the platform overview with accurate counts" do
    get admin_root_path

    assert_response :success
    assert_select "body", text: /#{User.count}/
  end

  test "index reflects the current maintenance mode status" do
    MaintenanceMode.enable!(message: "Scheduled downtime")

    get admin_root_path

    assert_response :success
    assert_match(/Maintenance mode is on/, @response.body)
  ensure
    MaintenanceMode.disable!
  end
end
