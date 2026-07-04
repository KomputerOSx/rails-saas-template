class RemoveDeviseFieldsFromUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users do |t|
      t.remove :encrypted_password, type: :string, null: false, default: ""
      t.remove :reset_password_token, type: :string
      t.remove :reset_password_sent_at, type: :datetime
      t.remove :remember_created_at, type: :datetime
      t.remove :unconfirmed_email, type: :string
      t.remove :sign_in_count, type: :integer, default: 0, null: false
      t.remove :current_sign_in_at, type: :datetime
      t.remove :current_sign_in_ip, type: :string
      t.remove :last_sign_in_ip, type: :string
    end

    change_column_default :users, :email, from: "", to: nil
  end
end
