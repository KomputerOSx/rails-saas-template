class CreatePermissions < ActiveRecord::Migration[8.1]
  def change
    create_table :permissions do |t|
      t.string :key, null: false
      t.string :description

      t.timestamps
    end

    add_index :permissions, :key, unique: true
  end
end
