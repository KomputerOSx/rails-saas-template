class Organization < ApplicationRecord
  SLUG_FORMAT = /\A[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?\z/
  RESERVED_SLUGS = %w[admin org invitations login logout password confirmations registration profile up rails].freeze

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :membership_roles, through: :memberships
  has_many :organization_invitations, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
    format: { with: SLUG_FORMAT },
    length: { maximum: 63 },
    exclusion: { in: RESERVED_SLUGS }

  # Every user gets exactly one of these at signup — see ConfirmationsController#create.
  # Name/slug are derived from the email local-part since registration only collects
  # email/password (no name field exists at signup time).
  def self.create_personal_for!(user)
    base = slug_base_for(user)
    name = name_for(user)

    organization = begin
      create!(name: name, slug: generate_unique_slug(base))
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      # A concurrent signup claimed the same slug between our uniqueness check and
      # the write — retry once with a random suffix rather than failing the signup.
      create!(name: name, slug: "#{base}-#{SecureRandom.alphanumeric(6).downcase}")
    end
    membership = organization.memberships.create!(user: user)

    owner_role = Role.find_or_create_by!(scope: :app, name: Role::APP_OWNER) do |role|
      role.permanent = true
      role.description = "Organization owner — full control; cannot be removed while sole owner"
    end
    membership.grant_role!(owner_role)

    organization
  end

  def self.name_for(user)
    local_part = user.email.to_s.split("@").first.to_s
    words = local_part.gsub(/[^a-zA-Z0-9]+/, " ").strip
    words.present? ? words.split.map(&:capitalize).join(" ") : "My Organization"
  end

  def self.slug_base_for(user)
    local_part = user.email.to_s.split("@").first.to_s.downcase
    base = local_part.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    base.presence || "org"
  end

  def self.generate_unique_slug(base)
    slug = base
    suffix = 2

    while exists?(slug: slug)
      slug = "#{base}-#{suffix}"
      suffix += 1
    end

    slug
  end
end
