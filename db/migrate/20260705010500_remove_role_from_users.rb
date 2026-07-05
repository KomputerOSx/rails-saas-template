class RemoveRoleFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, :role
    remove_column :users, :role, :string, default: "user", null: false
  end
end
