class AddPriceMigrationFieldsToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :pending_price_cents, :integer
    add_column :organizations, :grandfathered_at, :datetime
  end
end
