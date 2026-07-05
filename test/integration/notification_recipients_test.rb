require "test_helper"

class NotificationRecipientsTest < ActionDispatch::IntegrationTest
  test "a user can only mark_read/destroy their own notification recipient rows" do
    notification = Notification.deliver!(title: "Hello", body: "World", to: users(:two))
    other_recipient = notification.notification_recipients.first

    post login_path, params: { email: users(:one).email, password: "password123" }
    assert_redirected_to dashboard_path

    patch mark_read_notification_recipient_path(other_recipient)
    assert_response :not_found
  end

  test "mark_all_read zeroes the current user's unread count without touching other users'" do
    Notification.deliver!(title: "Mine", body: "Body", to: users(:one))
    Notification.deliver!(title: "Theirs", body: "Body", to: users(:two))

    post login_path, params: { email: users(:one).email, password: "password123" }
    assert_redirected_to dashboard_path

    assert_equal 1, users(:one).unread_notification_count

    patch mark_all_read_notification_recipients_path

    assert_equal 0, users(:one).unread_notification_count
    assert_equal 1, users(:two).unread_notification_count
  end

  test "destroy dismisses the notification for the current user only" do
    notification = Notification.deliver!(title: "Hello", body: "World", to: [ users(:one), users(:two) ])
    recipient = users(:one).notification_recipients.find_by(notification: notification)

    post login_path, params: { email: users(:one).email, password: "password123" }
    assert_redirected_to dashboard_path

    delete notification_recipient_path(recipient)

    assert_not_includes users(:one).notification_recipients.inbox.map(&:notification), notification
    assert_includes users(:two).notification_recipients.inbox.map(&:notification), notification
  end
end
