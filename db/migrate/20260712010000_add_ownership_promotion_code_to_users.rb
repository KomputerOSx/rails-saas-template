class AddOwnershipPromotionCodeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :ownership_promotion_code_digest, :string
    add_column :users, :ownership_promotion_code_sent_at, :datetime
  end
end
