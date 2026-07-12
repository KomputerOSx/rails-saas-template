require "test_helper"

class SitesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @organization = Organization.create_personal_for!(users(:one))
    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      @organization.update!(custom_domain: "shop.acme.test")
    end
  end

  test "renders organization info on a configured custom domain" do
    host! "shop.acme.test"

    get "/"

    assert_response :success
    assert_match @organization.name, response.body
    assert_match @organization.slug, response.body
    assert_match "shop.acme.test", response.body
  end

  test "returns not found for an unknown custom domain" do
    host! "unknown.acme.test"

    get "/"

    assert_response :not_found
  end

  test "catch-all paths on a custom domain still show the org page" do
    host! "shop.acme.test"

    get "/anything/here"

    assert_response :success
    assert_match @organization.name, response.body
  end

  test "health check is not swallowed by the custom domain catch-all" do
    host! "shop.acme.test"

    get "/up"

    assert_response :success
  end

  test "health check works when kamal-proxy uses a non-primary host" do
    host! "windtunnel-web-abc123"

    get "/up"

    assert_response :success
  end
end
