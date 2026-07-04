class AddAuthFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users do |t|
      t.string :password_digest, null: false, default: ""
      t.string :role, null: false, default: "user"
      t.integer :failed_login_attempts, null: false, default: 0
      t.datetime :locked_until
      t.string :totp_secret
      t.datetime :totp_enabled_at
      t.integer :totp_last_used_at
      t.string :first_name
      t.string :last_name
    end

    add_index :users, :role
    add_index :users, :locked_until
  end
end
