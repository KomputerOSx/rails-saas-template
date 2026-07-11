class AddCategoryToEmailCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :email_campaigns, :category, :string, default: "marketing", null: false
    add_index :email_campaigns, :category
  end
end
