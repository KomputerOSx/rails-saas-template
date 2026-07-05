class CreateRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :roles do |t|
      t.string :name, null: false
      t.string :scope, null: false, default: "app"
      t.string :description
      t.boolean :permanent, null: false, default: false

      t.timestamps
    end

    add_index :roles, [ :scope, :name ], unique: true
  end
end
