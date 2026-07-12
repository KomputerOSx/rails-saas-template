class AddOwnerDemotionCodeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :owner_demotion_code_digest, :string
    add_column :users, :owner_demotion_code_sent_at, :datetime
  end
end
