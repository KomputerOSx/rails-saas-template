class AddMaxWidthToEmailCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :email_campaigns, :max_width, :integer, default: 600, null: false
  end
end
