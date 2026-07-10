require "test_helper"

class OrganizationCustomDomainTest < ActiveSupport::TestCase
  setup do
    @organization = Organization.create_personal_for!(users(:one))
  end

  test "custom_domain_allowed? is true only on Growth" do
    assert_not @organization.custom_domain_allowed?

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      assert_not @organization.custom_domain_allowed?
    end

    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      assert @organization.custom_domain_allowed?
    end
  end

  test "rejects custom_domain on Free or Starter" do
    assert_not @organization.update(custom_domain: "shop.example.com")
    assert_includes @organization.errors[:custom_domain], "requires the Growth plan"
    @organization.reload

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      assert_not @organization.update(custom_domain: "shop.example.com")
      assert_includes @organization.errors[:custom_domain], "requires the Growth plan"
    end
  end

  test "accepts a valid custom_domain on Growth and normalizes it" do
    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      assert @organization.update(custom_domain: "WWW.Shop.Example.COM")
      assert_equal "shop.example.com", @organization.reload.custom_domain
    end
  end

  test "rejects invalid custom_domain format" do
    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      assert_not @organization.update(custom_domain: "not a domain")
      assert_not @organization.update(custom_domain: "localhost")
      assert_not @organization.update(custom_domain: "http://shop.example.com")
    end
  end

  test "enforces unique custom_domain" do
    other = Organization.create_personal_for!(users(:two))

    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      assert @organization.update(custom_domain: "shop.example.com")
    end

    with_active_subscription(other, Billing::Plans::GROWTH) do
      assert_not other.update(custom_domain: "shop.example.com")
      assert_includes other.errors[:custom_domain], "has already been taken"
    end
  end

  test "clears domain cache when custom_domain changes" do
    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      @organization.update!(custom_domain: "old.example.com")
      Rails.cache.write("#{Organization::DOMAIN_ORG_CACHE_PREFIX}old.example.com", @organization.id)
      Rails.cache.write("#{Organization::DOMAIN_ORG_CACHE_PREFIX}new.example.com", 999)

      @organization.update!(custom_domain: "new.example.com")

      assert_nil Rails.cache.read("#{Organization::DOMAIN_ORG_CACHE_PREFIX}old.example.com")
      assert_nil Rails.cache.read("#{Organization::DOMAIN_ORG_CACHE_PREFIX}new.example.com")
    end
  end

  test "find_id_by_custom_domain caches the organization id" do
    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      @organization.update!(custom_domain: "shop.example.com")
    end

    assert_equal @organization.id, Organization.find_id_by_custom_domain("shop.example.com")
    assert_equal @organization.id, Rails.cache.read("#{Organization::DOMAIN_ORG_CACHE_PREFIX}shop.example.com")
  end

  test "clear_custom_domain_if_disallowed! removes the domain when not on Growth" do
    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      @organization.update!(custom_domain: "shop.example.com")
    end

    @organization.payment_processor.subscription.update!(status: "canceled", ends_at: 1.day.ago)
    @organization.clear_custom_domain_if_disallowed!

    assert_nil @organization.reload.custom_domain
  end
end
