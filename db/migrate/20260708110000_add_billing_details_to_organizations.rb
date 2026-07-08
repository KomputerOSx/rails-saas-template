class AddBillingDetailsToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :billing_name, :string
    add_column :organizations, :billing_address_line1, :string
    add_column :organizations, :billing_address_line2, :string
    add_column :organizations, :billing_address_city, :string
    add_column :organizations, :billing_address_state, :string
    add_column :organizations, :billing_address_postal_code, :string
    add_column :organizations, :billing_address_country, :string
  end
end
