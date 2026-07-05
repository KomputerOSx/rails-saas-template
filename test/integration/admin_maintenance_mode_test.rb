require "test_helper"

class AdminMaintenanceModeTest < ActionDispatch::IntegrationTest
  teardown { FileUtils.rm_f(MaintenanceMode.file_path) }

  def sign_in_as_system_admin(user)
    role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }
    user.grant_role!(role)
    post login_path, params: { email: user.email, password: "password123" }
    assert_redirected_to dashboard_path
  end

  test "non-system-admin cannot reach the maintenance mode page" do
    post login_path, params: { email: users(:one).email, password: "password123" }
    assert_redirected_to dashboard_path

    assert_difference -> { AuditLog.where(event_type: :authorization_denied).count }, 1 do
      get edit_admin_maintenance_mode_path
    end

    assert_redirected_to root_path
  end

  test "system admin can enable maintenance mode with a message, audited" do
    sign_in_as_system_admin(users(:one))

    assert_difference -> { AuditLog.where(event_type: :maintenance_mode_enabled).count }, 1 do
      patch admin_maintenance_mode_path, params: { maintenance_mode: { enabled: "1", message: "Upgrading the database." } }
    end

    assert_redirected_to edit_admin_maintenance_mode_path
    status = MaintenanceMode.status
    assert status[:enabled]
    assert_equal "Upgrading the database.", status[:message]
  end

  test "system admin can disable maintenance mode, audited, and the file is removed" do
    sign_in_as_system_admin(users(:one))
    MaintenanceMode.enable!(message: "Upgrading.")

    assert_difference -> { AuditLog.where(event_type: :maintenance_mode_disabled).count }, 1 do
      patch admin_maintenance_mode_path, params: { maintenance_mode: { enabled: "0", message: "" } }
    end

    assert_not File.exist?(MaintenanceMode.file_path)
  end

  test "enabling with a blank message re-renders the form and does not enable" do
    sign_in_as_system_admin(users(:one))

    patch admin_maintenance_mode_path, params: { maintenance_mode: { enabled: "1", message: "" } }

    assert_response :unprocessable_entity
    assert_not MaintenanceMode.enabled?
  end

  test "force logout all destroys every other session but keeps the admin signed in, audited" do
    admin = users(:one)
    sign_in_as_system_admin(admin)

    other_user = users(:two)
    other_user.sessions.create!(expires_at: 1.hour.from_now)
    admin_other_session = admin.sessions.create!(expires_at: 1.hour.from_now)

    assert_difference -> { AuditLog.where(event_type: :sessions_force_logged_out).count }, 1 do
      post force_logout_all_admin_maintenance_mode_path
    end

    assert_redirected_to edit_admin_maintenance_mode_path
    assert_equal 0, other_user.sessions.count
    assert_not Session.exists?(admin_other_session.id)

    # The current session (the one used to make this very request) survives.
    get admin_root_path
    assert_response :success
  end
end
