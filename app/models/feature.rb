class Feature < ApplicationRecord
  has_many :feature_organization_accesses, dependent: :destroy
  # Scoped to currently-enabled accesses only, so `#organization_ids` (used to
  # pre-check the admin form's checkbox grid) reflects granted organizations, not
  # ones that were granted and later revoked (those rows are kept, just disabled).
  has_many :organizations, -> { merge(FeatureOrganizationAccess.enabled) }, through: :feature_organization_accesses

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true

  scope :available, -> { where(enabled: true) }
  scope :available_to_organization, ->(organization) {
    available
      .joins(:feature_organization_accesses)
      .where(feature_organization_accesses: { organization_id: organization.id, enabled: true })
      .distinct
  }

  def available_to_organization?(organization)
    enabled? && feature_organization_accesses.enabled.exists?(organization_id: organization.id)
  end
end
