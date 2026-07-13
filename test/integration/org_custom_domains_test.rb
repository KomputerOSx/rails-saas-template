require "test_helper"

class OrgCustomDomainsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "Growth owner can set and remove a custom domain" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      post org_custom_domain_path, params: { organization: { custom_domain: "shop.example.com" } }

      assert_redirected_to org_settings_path
      assert_equal "shop.example.com", @organization.reload.custom_domain
      assert AuditLog.exists?(event_type: :custom_domain_updated)

      delete org_custom_domain_path

      assert_redirected_to org_settings_path
      assert_nil @organization.reload.custom_domain
      assert AuditLog.exists?(event_type: :custom_domain_removed)
    end
  end

  test "Free plan cannot set a custom domain" do
    post login_path, params: { email: @owner.email, password: "password123" }

    post org_custom_domain_path, params: { organization: { custom_domain: "shop.example.com" } }

    assert_redirected_to org_settings_path
    assert_match(/Growth plan/i, flash[:alert].to_s)
    assert_nil @organization.reload.custom_domain
  end

  test "settings page shows upgrade CTA when not on Growth" do
    post login_path, params: { email: @owner.email, password: "password123" }

    get org_settings_path

    assert_response :success
    assert_match(/Custom domains are available on the Growth plan/i, response.body)
    assert_match billing_path, response.body
  end

  test "settings page shows domain form on Growth" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      get org_settings_path

      assert_response :success
      assert_match(/organization\[custom_domain\]/, response.body)
      assert_match(/>Type</, response.body)
      assert_match(/>Name</, response.body)
      assert_match(/Points to/, response.body)
      assert_match(/\bCNAME\b/, response.body)
      assert_match(/data-controller="clipboard"/, response.body)
      assert_match(/content_copy/, response.body)
      assert_match(/card border border-base-300/, response.body)
    end
  end

  test "status endpoint reports DNS check JSON" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      @organization.update!(custom_domain: "shop.acme.test")

      CustomDomainDnsCheck.stub(:call, CustomDomainDnsCheck::Result.new(status: :ready, message: "DNS looks good.")) do
        get status_org_custom_domain_path, as: :json

        assert_response :success
        body = JSON.parse(response.body)
        assert_equal "ready", body["status"]
        assert_match(/DNS looks good/i, body["message"])
      end
    end
  end

  test "settings page polls DNS status when a domain is set" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      @organization.update!(custom_domain: "shop.acme.test")

      get org_settings_path

      assert_response :success
      assert_match(/data-controller="custom-domain-status"/, response.body)
      assert_match(%r{data-custom-domain-status-url-value="[^"]*custom_domain/status"}, response.body)
      assert_match(/badge-warning/, response.body)
    end
  end

  test "a plain member cannot set a custom domain" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      post org_custom_domain_path, params: { organization: { custom_domain: "shop.example.com" } }

      assert_redirected_to root_path
      assert_nil @organization.reload.custom_domain
    end
  end
end
