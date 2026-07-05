require "test_helper"

class NotificationRecipientTest < ActiveSupport::TestCase
  test "mark_read! sets read_at and is idempotent" do
    notification = Notification.deliver!(title: "Hello", body: "World", to: users(:one))
    recipient = notification.notification_recipients.first

    recipient.mark_read!
    first_read_at = recipient.read_at
    assert_not_nil first_read_at

    travel 1.hour do
      recipient.mark_read!
    end

    assert_equal first_read_at, recipient.reload.read_at
  end

  test "dismiss! sets dismissed_at" do
    notification = Notification.deliver!(title: "Hello", body: "World", to: users(:one))
    recipient = notification.notification_recipients.first

    recipient.dismiss!

    assert_not_nil recipient.dismissed_at
  end

  test "inbox scope excludes dismissed rows and rows whose notification is withdrawn" do
    active_notification = Notification.deliver!(title: "Active", body: "Body", to: users(:one))
    dismissed_notification = Notification.deliver!(title: "Dismissed", body: "Body", to: users(:one))
    withdrawn_notification = Notification.deliver!(title: "Withdrawn", body: "Body", to: users(:one))

    dismissed_notification.notification_recipients.first.dismiss!
    withdrawn_notification.withdraw!

    inbox = users(:one).notification_recipients.inbox

    assert_includes inbox.map(&:notification), active_notification
    assert_not_includes inbox.map(&:notification), dismissed_notification
    assert_not_includes inbox.map(&:notification), withdrawn_notification
  end

  test "unread scope excludes read rows" do
    notification = Notification.deliver!(title: "Hello", body: "World", to: users(:one))
    recipient = notification.notification_recipients.first

    assert_includes NotificationRecipient.unread, recipient

    recipient.mark_read!

    assert_not_includes NotificationRecipient.unread, recipient
  end
end
