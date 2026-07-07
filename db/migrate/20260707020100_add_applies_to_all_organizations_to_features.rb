class AddAppliesToAllOrganizationsToFeatures < ActiveRecord::Migration[8.1]
  def change
    add_column :features, :applies_to_all_organizations, :boolean, null: false, default: false
  end
end
