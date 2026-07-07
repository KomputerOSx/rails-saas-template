class Feature < ApplicationRecord
  has_many :feature_organization_accesses, dependent: :destroy
  # Scoped to currently-enabled accesses only, so `#organization_ids` (used to
  # pre-check the admin form's checkbox grid) reflects granted organizations, not
  # ones that were granted and later revoked (those rows are kept, just disabled).
  has_many :organizations, -> { merge(FeatureOrganizationAccess.enabled) }, through: :feature_organization_accesses

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true

  scope :available, -> { where(enabled: true) }
  # Uses an EXISTS OR rather than an inner join so a feature with
  # applies_to_all_organizations set still matches organizations that have no
  # FeatureOrganizationAccess row at all (e.g. ones created after the flag was turned on).
  scope :available_to_organization, ->(organization) {
    available.where(
      "features.applies_to_all_organizations = ? OR EXISTS (
        SELECT 1 FROM feature_organization_accesses
        WHERE feature_organization_accesses.feature_id = features.id
        AND feature_organization_accesses.organization_id = ?
        AND feature_organization_accesses.enabled = ?
      )", true, organization.id, true
    )
  }

  def available_to_organization?(organization)
    return false unless enabled?

    applies_to_all_organizations? || feature_organization_accesses.enabled.exists?(organization_id: organization.id)
  end
end
