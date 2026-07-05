require "test_helper"

class MaintenanceModeTest < ActiveSupport::TestCase
  teardown { FileUtils.rm_f(MaintenanceMode.file_path) }

  test "enable! and disable! round-trip through the file" do
    assert_not MaintenanceMode.enabled?

    MaintenanceMode.enable!(message: "Down for maintenance.")

    status = MaintenanceMode.status
    assert status[:enabled]
    assert_equal "Down for maintenance.", status[:message]

    MaintenanceMode.disable!

    assert_not File.exist?(MaintenanceMode.file_path)
    status = MaintenanceMode.status
    assert_not status[:enabled]
    assert_nil status[:message]
  end

  test "a corrupted file fails safe to disabled" do
    File.write(MaintenanceMode.file_path, "not valid json{{{")

    status = MaintenanceMode.status

    assert_not status[:enabled]
    assert_nil status[:message]
  end
end
