require "test_helper"

class ProfileTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    post login_path, params: { email: users(:one).email, password: "password123" }
  end

  test "show renders the current user's profile" do
    get profile_path
    assert_response :success
  end

  test "update changes the user's name" do
    patch profile_path, params: { user: { first_name: "Ada", last_name: "Lovelace" } }

    assert_redirected_to profile_path
    assert_equal "Ada", users(:one).reload.first_name
    assert_equal "Lovelace", users(:one).reload.last_name
  end

  test "send_deletion_code emails a code and responds with json" do
    assert_enqueued_emails 1 do
      post profile_deletion_code_path
    end

    assert_response :success
    assert_equal({ "sent" => true }, JSON.parse(@response.body))
  end

  test "destroy requires the typed email to match" do
    perform_enqueued_jobs { post profile_deletion_code_path }
    code = ActionMailer::Base.deliveries.last.body.encoded[/(\d{6})/, 1]

    delete profile_path, params: { typed_confirmation: "wrong@example.com", code: code.chars }

    assert_redirected_to profile_path
    assert User.exists?(users(:one).id)
  end

  test "destroy requires a valid, unexpired code" do
    delete profile_path, params: { typed_confirmation: users(:one).email, code: "000000".chars }

    assert_redirected_to profile_path
    assert User.exists?(users(:one).id)
  end

  test "destroy deletes the account when confirmation email and code both match" do
    perform_enqueued_jobs { post profile_deletion_code_path }
    code = ActionMailer::Base.deliveries.last.body.encoded[/(\d{6})/, 1]

    delete profile_path, params: { typed_confirmation: users(:one).email, code: code.chars }

    assert_redirected_to root_path
    assert_not User.exists?(users(:one).id)
  end

  test "new_totp shows a QR code for setup" do
    get new_profile_totp_path
    assert_response :success
  end

  test "new_totp redirects if TOTP is already enabled" do
    users(:one).enable_totp!(ROTP::Base32.random_base32)

    get new_profile_totp_path

    assert_redirected_to profile_path
  end

  test "create_totp enables TOTP with a valid code and current password" do
    get new_profile_totp_path
    secret = @request.session[:pending_totp_secret]
    valid_code = ROTP::TOTP.new(secret).now

    post profile_totp_path, params: { current_password: "password123", code: valid_code.chars }

    assert_redirected_to profile_path
    assert users(:one).reload.totp_enabled?
  end

  test "create_totp rejects an incorrect current password" do
    get new_profile_totp_path
    secret = @request.session[:pending_totp_secret]
    valid_code = ROTP::TOTP.new(secret).now

    post profile_totp_path, params: { current_password: "wrong-password", code: valid_code.chars }

    assert_response :unprocessable_entity
    assert_not users(:one).reload.totp_enabled?
  end

  test "destroy_totp disables TOTP with the correct password" do
    users(:one).enable_totp!(ROTP::Base32.random_base32)

    delete "/profile/totp", params: { current_password: "password123" }

    assert_redirected_to profile_path
    assert_not users(:one).reload.totp_enabled?
  end
end
