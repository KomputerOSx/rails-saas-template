require "test_helper"

class OrganizationInvitationTest < ActiveSupport::TestCase
  setup do
    @organization = Organization.create!(name: "Acme", slug: "acme")
    @role = Role.find_or_create_by!(scope: :app, name: Role::APP_USER)
  end

  test "generate_for! returns a usable record and the raw token digests correctly" do
    record, raw_token = OrganizationInvitation.generate_for!(organization: @organization, email: "New.Person@Example.com ", role: @role)

    assert record.persisted?
    assert_equal "new.person@example.com", record.email
    assert_equal OrganizationInvitation.digest(raw_token), record.token_digest
    assert record.usable?
  end

  test "generate_for! revokes any outstanding invitation to the same email" do
    _first, first_raw = OrganizationInvitation.generate_for!(organization: @organization, email: "person@example.com", role: @role)
    _second, second_raw = OrganizationInvitation.generate_for!(organization: @organization, email: "person@example.com", role: @role)

    assert_nil OrganizationInvitation.find_usable(first_raw)
    assert OrganizationInvitation.find_usable(second_raw).usable?
  end

  test "find_usable returns nil for a blank, unknown, expired, revoked, or accepted token" do
    assert_nil OrganizationInvitation.find_usable(nil)
    assert_nil OrganizationInvitation.find_usable("")
    assert_nil OrganizationInvitation.find_usable("not-a-real-token")

    record, raw_token = OrganizationInvitation.generate_for!(organization: @organization, email: "expired@example.com", role: @role)
    record.update!(expires_at: 1.minute.ago)
    assert_nil OrganizationInvitation.find_usable(raw_token)

    record2, raw_token2 = OrganizationInvitation.generate_for!(organization: @organization, email: "revoked@example.com", role: @role)
    record2.revoke!
    assert_nil OrganizationInvitation.find_usable(raw_token2)

    record3, raw_token3 = OrganizationInvitation.generate_for!(organization: @organization, email: "accepted@example.com", role: @role)
    record3.update!(accepted_at: Time.current)
    assert_nil OrganizationInvitation.find_usable(raw_token3)
  end

  test "accept! creates a membership with the invited role and marks the invitation accepted" do
    record, _raw_token = OrganizationInvitation.generate_for!(organization: @organization, email: "invitee@example.com", role: @role)
    user = User.create!(email: "invitee@example.com", password: "Xk92!vTqZmR7", confirmed_at: Time.current)

    membership = record.accept!(user)

    assert record.reload.accepted_at.present?
    assert_equal @organization, membership.organization
    assert_includes membership.roles, @role
  end

  test "revoke! sets revoked_at and makes the invitation unusable" do
    record, _raw_token = OrganizationInvitation.generate_for!(organization: @organization, email: "invitee@example.com", role: @role)

    record.revoke!

    assert record.revoked_at.present?
    assert_not record.usable?
  end

  test "a system-scoped role is rejected" do
    system_role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN)

    invitation = @organization.organization_invitations.new(
      email: "invitee@example.com",
      role: system_role,
      token_digest: OrganizationInvitation.digest(SecureRandom.hex),
      expires_at: 7.days.from_now
    )

    assert_not invitation.valid?
    assert_includes invitation.errors[:role], "must be app-scoped"
  end
end
