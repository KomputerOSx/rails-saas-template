class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.references :user, null: true, foreign_key: true
      t.string :event_type, null: false
      t.string :resource_type
      t.bigint :resource_id
      t.string :ip_address
      t.string :user_agent
      t.text :metadata

      t.timestamps
    end

    add_index :audit_logs, :event_type
    add_index :audit_logs, :created_at
    add_index :audit_logs, [ :user_id, :event_type ]
    add_index :audit_logs, [ :resource_type, :resource_id ], name: "index_audit_logs_on_resource"
  end
end
