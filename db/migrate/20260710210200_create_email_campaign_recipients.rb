class CreateEmailCampaignRecipients < ActiveRecord::Migration[8.1]
  def change
    create_table :email_campaign_recipients do |t|
      t.references :email_campaign, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :sent_at
      t.datetime :failed_at
      t.string :error_message

      t.timestamps
    end

    add_index :email_campaign_recipients, [ :email_campaign_id, :user_id ], unique: true,
      name: "idx_email_campaign_recipients_unique"
  end
end
