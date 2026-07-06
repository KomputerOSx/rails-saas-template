class FeatureOrganizationAccess < ApplicationRecord
  belongs_to :feature
  belongs_to :organization

  validates :organization_id, uniqueness: { scope: :feature_id }

  scope :enabled, -> { where(enabled: true) }
end
