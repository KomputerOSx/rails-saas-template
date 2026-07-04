class AddEmailChangeFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users do |t|
      t.string :unconfirmed_email
      t.string :email_change_token_old
      t.string :email_change_token_new
      t.datetime :email_change_requested_at
      t.datetime :email_change_old_confirmed_at
      t.datetime :email_change_new_confirmed_at
    end

    add_index :users, :email_change_token_old, unique: true
    add_index :users, :email_change_token_new, unique: true
  end
end
