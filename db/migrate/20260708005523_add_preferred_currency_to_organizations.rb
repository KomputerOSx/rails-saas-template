class AddPreferredCurrencyToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :preferred_currency, :string, null: false, default: "usd"
  end
end
