class CreateFeatures < ActiveRecord::Migration[8.1]
  def change
    create_table :features do |t|
      t.string  :key, null: false
      t.string  :name, null: false
      t.text    :description
      t.boolean :enabled, null: false, default: false
      t.boolean :manager_activation_required, null: false, default: true

      t.timestamps
    end

    add_index :features, :key, unique: true
  end
end
