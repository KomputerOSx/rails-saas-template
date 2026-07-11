class RemoveBgColorAndFgColorFromEmailCampaigns < ActiveRecord::Migration[8.1]
  def change
    remove_column :email_campaigns, :bg_color, :string, default: "#ffffff", null: false
    remove_column :email_campaigns, :fg_color, :string, default: "#ffffff", null: false
  end
end
