class AddCustomDomainToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :custom_domain, :string
    add_index :organizations, :custom_domain, unique: true
  end
end
