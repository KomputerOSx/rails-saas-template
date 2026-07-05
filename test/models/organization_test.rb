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
end
