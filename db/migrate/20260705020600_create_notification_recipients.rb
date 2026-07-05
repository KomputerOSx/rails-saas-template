class CreateNotificationRecipients < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_recipients do |t|
      t.references :notification, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :read_at
      t.datetime :dismissed_at

      t.timestamps
    end

    add_index :notification_recipients, [ :notification_id, :user_id ], unique: true,
      name: "idx_notification_recipients_unique"
    add_index :notification_recipients, [ :user_id, :dismissed_at, :read_at ],
      name: "idx_notification_recipients_inbox"
  end
end
