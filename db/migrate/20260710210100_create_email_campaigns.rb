class CreateEmailCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :email_campaigns do |t|
      t.string :subject, null: false
      t.text :body_html, null: false
      t.string :status, null: false, default: "draft"
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :sent_at

      t.timestamps
    end

    add_index :email_campaigns, :status
    add_index :email_campaigns, :created_at
  end
end
