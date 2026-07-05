require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  test "deliver! with a single user creates one recipient" do
    notification = Notification.deliver!(title: "Hello", body: "World", to: users(:one))

    assert_equal 1, notification.notification_recipients.count
    assert_equal [ users(:one) ], notification.recipients
  end

  test "deliver! with an array of users creates one recipient per user" do
    notification = Notification.deliver!(title: "Hello", body: "World", to: [ users(:one), users(:two) ])

    assert_equal 2, notification.notification_recipients.count
    assert_equal [ users(:one), users(:two) ].sort_by(&:id), notification.recipients.sort_by(&:id)
  end

  test "deliver! with a relation (User.all) fans out to every user" do
    notification = Notification.deliver!(title: "Hello", body: "World", to: User.all)

    assert_equal User.count, notification.notification_recipients.count
  end

  test "deliver! raises ArgumentError when given no recipients" do
    assert_raises(ArgumentError) do
      Notification.deliver!(title: "Hello", body: "World", to: [])
    end
  end

  test "created_by is optional" do
    notification = Notification.deliver!(title: "Hello", body: "World", to: users(:one), created_by: nil)

    assert_nil notification.created_by
  end

  test "withdraw! sets withdrawn_at and updates active/withdrawn scopes" do
    notification = Notification.deliver!(title: "Hello", body: "World", to: users(:one))

    assert_includes Notification.active, notification
    assert_not_includes Notification.withdrawn, notification

    notification.withdraw!

    assert notification.withdrawn?
    assert_not_includes Notification.active, notification
    assert_includes Notification.withdrawn, notification
  end
end
