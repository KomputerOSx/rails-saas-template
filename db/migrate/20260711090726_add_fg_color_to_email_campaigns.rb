class AddFgColorToEmailCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :email_campaigns, :fg_color, :string, default: "#ffffff", null: false
  end
end
