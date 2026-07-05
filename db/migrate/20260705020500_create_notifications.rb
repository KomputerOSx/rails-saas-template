class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :withdrawn_at

      t.timestamps
    end

    add_index :notifications, :withdrawn_at
    add_index :notifications, :created_at
  end
end
