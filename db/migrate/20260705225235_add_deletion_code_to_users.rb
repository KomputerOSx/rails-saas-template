class AddDeletionCodeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :account_deletion_code_digest, :string
    add_column :users, :account_deletion_code_sent_at, :datetime
  end
end
