class OrganizationInvitation < ApplicationRecord
  EXPIRY = 7.days
  TOKEN_BYTES = 32

  MemberLimitReached = Class.new(StandardError)

  belongs_to :organization
  belongs_to :role
  belongs_to :invited_by, class_name: "User", optional: true

  scope :outstanding, -> { where(accepted_at: nil, revoked_at: nil) }
  scope :active, -> { outstanding.where("expires_at > ?", Time.current) }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate :role_must_be_app_scoped

  def self.generate_for!(organization:, email:, role:, invited_by: nil)
    raw_token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
    normalized_email = email.to_s.strip.downcase

    transaction do
      organization.organization_invitations.outstanding.where(email: normalized_email)
        .update_all(revoked_at: Time.current, updated_at: Time.current)

      record = organization.organization_invitations.create!(
        email: normalized_email,
        role: role,
        invited_by: invited_by,
        token_digest: digest(raw_token),
        expires_at: EXPIRY.from_now
      )

      [ record, raw_token ]
    end
  end

  def self.find_usable(raw_token)
    return nil if raw_token.blank?

    active.includes(:organization, :role, :invited_by).find_by(token_digest: digest(raw_token.to_s))
  end

  def self.digest(raw_token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, raw_token.to_s)
  end

  def usable?
    revoked_at.blank? && accepted_at.blank? && expires_at.future?
  end

  # Raises MemberLimitReached instead of joining once the organization is full - checked
  # here (not just at invite-creation time) since this is the single call path shared by
  # every acceptance route (direct accept, and the login/signup/confirmation resumption
  # flows in InvitationResumption), so the limit can't be bypassed by resuming a stashed
  # invitation instead of clicking "Accept" directly.
  #
  # Uses ">" rather than Organization#at_member_limit?'s ">=": this invitation already
  # occupies one of the organization's reserved seats (it counts toward
  # member_count_with_pending as an outstanding invitation), so converting it into a real
  # membership doesn't add a new occupant - it's only blocked if the org has become
  # genuinely oversubscribed since the invite was sent (e.g. a plan downgrade).
  def accept!(user)
    transaction do
      already_member = organization.memberships.exists?(user: user)
      raise MemberLimitReached if !already_member && organization.member_count_with_pending > organization.member_limit

      membership = organization.memberships.find_or_create_by!(user: user)
      membership.grant_role!(role, granted_by: invited_by)
      update!(accepted_at: Time.current)
      membership
    end
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  private

  def role_must_be_app_scoped
    errors.add(:role, "must be app-scoped") unless role&.app?
  end
end
