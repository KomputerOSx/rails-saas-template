class CreateMembershipRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :membership_roles do |t|
      t.references :membership, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.references :granted_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :membership_roles, [ :membership_id, :role_id ], unique: true
  end
end
