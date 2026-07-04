class ConvertConfirmationAndEmailChangeToCodes < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, :confirmation_token, unique: true, if_exists: true
    remove_index :users, :email_change_token_old, unique: true, if_exists: true
    remove_index :users, :email_change_token_new, unique: true, if_exists: true

    change_table :users do |t|
      t.remove :confirmation_token, type: :string
      t.remove :confirmation_sent_at, type: :datetime
      t.remove :email_change_token_old, type: :string
      t.remove :email_change_token_new, type: :string

      # Signup confirmation is now handled entirely via PendingRegistration (Rails.cache) —
      # no `users` row exists until the code is confirmed, so no code/attempts columns needed here.
      t.string :email_change_old_code_digest
      t.string :email_change_new_code_digest
      t.integer :email_change_attempts, null: false, default: 0
    end
  end
end
