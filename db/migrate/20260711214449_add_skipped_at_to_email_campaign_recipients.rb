class AddSkippedAtToEmailCampaignRecipients < ActiveRecord::Migration[8.1]
  def change
    add_column :email_campaign_recipients, :skipped_at, :datetime
  end
end
