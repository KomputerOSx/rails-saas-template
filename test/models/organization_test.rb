require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "slug must be unique and DNS-safe" do
    Organization.create!(name: "Acme", slug: "acme")

    duplicate = Organization.new(name: "Acme Two", slug: "acme")
    assert_not duplicate.valid?

    invalid = Organization.new(name: "Bad", slug: "Not_Valid!")
    assert_not invalid.valid?
  end

  test "reserved slugs are rejected" do
    org = Organization.new(name: "Admin", slug: "admin")
    assert_not org.valid?
  end

  test "create_personal_for! derives name and slug from the email local-part" do
    user = User.create!(email: "jane.doe@example.com", password: "Tr8kMvln52", password_confirmation: "Tr8kMvln52", confirmed_at: Time.current)

    organization = Organization.create_personal_for!(user)

    assert_equal "Jane Doe", organization.name
    assert_equal "jane-doe", organization.slug
    assert user.memberships.exists?(organization: organization)
    assert user.memberships.first.has_role?(Role::APP_OWNER, scope: :app)
  end

  test "create_personal_for! resolves slug collisions across different email domains" do
    user_one = User.create!(email: "jane.doe@gmail.com", password: "Tr8kMvln52", password_confirmation: "Tr8kMvln52", confirmed_at: Time.current)
    user_two = User.create!(email: "jane.doe@yahoo.com", password: "Tr8kMvln52", password_confirmation: "Tr8kMvln52", confirmed_at: Time.current)

    org_one = Organization.create_personal_for!(user_one)
    org_two = Organization.create_personal_for!(user_two)

    assert_not_equal org_one.slug, org_two.slug
    assert_equal "jane-doe", org_one.slug
    assert_equal "jane-doe-2", org_two.slug
  end

  test "current_plan defaults to Free with no subscription" do
    organization = Organization.create_personal_for!(users(:one))

    assert_equal Billing::Plans::FREE, organization.current_plan
    assert_equal 1, organization.member_limit
  end

  test "current_plan resolves to the plan matching the active subscription's price" do
    organization = Organization.create_personal_for!(users(:one))

    with_active_subscription(organization, Billing::Plans::STARTER) do
      assert_equal Billing::Plans::STARTER, organization.current_plan
      assert_equal 5, organization.member_limit
    end
  end

  test "current_plan falls back to Free once the subscription is canceled" do
    organization = Organization.create_personal_for!(users(:one))

    with_active_subscription(organization, Billing::Plans::STARTER) do
      organization.payment_processor.subscription.update!(status: "canceled", ends_at: 1.day.ago)
    end

    assert_equal Billing::Plans::FREE, organization.current_plan
  end

  test "member_count_with_pending counts memberships and outstanding invitations, not revoked ones" do
    organization = Organization.create_personal_for!(users(:one))
    role = Role.find_or_create_by!(scope: :app, name: Role::APP_USER)

    assert_equal 1, organization.member_count_with_pending

    invitation, = OrganizationInvitation.generate_for!(organization: organization, email: "a@example.com", role: role)
    assert_equal 2, organization.member_count_with_pending

    invitation.revoke!
    assert_equal 1, organization.member_count_with_pending
  end

  test "at_member_limit? is true for a fresh Free-tier org (the owner already fills the sole seat)" do
    organization = Organization.create_personal_for!(users(:one))

    assert organization.at_member_limit?
    assert_equal 0, organization.remaining_seats
  end

  test "at_member_limit? is false while a paid plan has open seats" do
    organization = Organization.create_personal_for!(users(:one))

    with_active_subscription(organization, Billing::Plans::STARTER) do
      assert_not organization.at_member_limit?
      assert_equal 4, organization.remaining_seats
    end
  end

  test "over_member_limit? reflects the over_member_limit_at flag, not a live recompute" do
    organization = Organization.create_personal_for!(users(:one))

    assert_not organization.over_member_limit?
    organization.update!(over_member_limit_at: Time.current)
    assert organization.over_member_limit?
  end
end
