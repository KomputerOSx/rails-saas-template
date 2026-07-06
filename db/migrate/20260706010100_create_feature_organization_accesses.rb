class CreateFeatureOrganizationAccesses < ActiveRecord::Migration[8.1]
  def change
    create_table :feature_organization_accesses do |t|
      t.references :feature, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :feature_organization_accesses, [ :feature_id, :organization_id ],
      unique: true, name: "index_feature_org_accesses_on_feature_and_org"
  end
end
