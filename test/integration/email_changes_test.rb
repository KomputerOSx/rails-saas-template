require "test_helper"

class EmailChangesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    post login_path, params: { email: users(:one).email, password: "password123" }
  end

  test "new renders the change-email form" do
    get new_profile_email_change_path
    assert_response :success
  end

  test "create starts an email change and emails a code to the old address" do
    assert_enqueued_emails 1 do
      post profile_email_change_path, params: { email: "new-address@example.com" }
    end

    assert_response :success
    assert_equal "new-address@example.com", users(:one).reload.unconfirmed_email
  end

  test "create rejects an email already in use" do
    post profile_email_change_path, params: { email: users(:two).email }

    assert_response :unprocessable_entity
    assert_nil users(:one).reload.unconfirmed_email
  end

  test "confirm_old accepts the correct code and emails a code to the new address" do
    code = current_user_start_email_change!

    assert_enqueued_emails 1 do
      post confirm_old_profile_email_change_path, params: { code: code.chars }
    end

    assert_response :success
    assert users(:one).reload.email_change_old_confirmed_at.present?
  end

  test "confirm_old rejects an incorrect code" do
    current_user_start_email_change!

    post confirm_old_profile_email_change_path, params: { code: "000000".chars }

    assert_response :unprocessable_entity
    assert_nil users(:one).reload.email_change_old_confirmed_at
  end

  test "confirm_new completes the change on the correct code" do
    old_code = current_user_start_email_change!
    perform_enqueued_jobs { post confirm_old_profile_email_change_path, params: { code: old_code.chars } }
    new_code = ActionMailer::Base.deliveries.last.body.encoded[/(\d{6})/, 1]

    post confirm_new_profile_email_change_path, params: { code: new_code.chars }

    assert_response :success
    assert_equal "new-address@example.com", users(:one).reload.email
    assert_nil users(:one).unconfirmed_email
  end

  test "confirm_new rejects an incorrect code" do
    old_code = current_user_start_email_change!
    post confirm_old_profile_email_change_path, params: { code: old_code.chars }

    post confirm_new_profile_email_change_path, params: { code: "000000".chars }

    assert_response :unprocessable_entity
    assert_not_equal "new-address@example.com", users(:one).reload.email
  end

  test "destroy cancels a pending email change" do
    current_user_start_email_change!

    delete profile_email_change_path

    assert_redirected_to profile_path
    assert_nil users(:one).reload.unconfirmed_email
  end

  private

  def current_user_start_email_change!
    code = nil
    perform_enqueued_jobs do
      post profile_email_change_path, params: { email: "new-address@example.com" }
    end
    ActionMailer::Base.deliveries.last.body.encoded[/(\d{6})/, 1]
  end
end
