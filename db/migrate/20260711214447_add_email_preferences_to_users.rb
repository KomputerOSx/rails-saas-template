class AddEmailPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_preferences, :json, default: {}, null: false
  end
end
