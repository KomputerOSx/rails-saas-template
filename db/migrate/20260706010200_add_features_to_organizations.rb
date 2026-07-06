class AddFeaturesToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :features, :text
  end
end
