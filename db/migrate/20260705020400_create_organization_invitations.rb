class CreateOrganizationInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :organization_invitations do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :email, null: false
      t.references :role, null: false, foreign_key: true
      t.references :invited_by, foreign_key: { to_table: :users }
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :organization_invitations, :token_digest, unique: true
    add_index :organization_invitations, [ :organization_id, :email ], unique: true,
      where: "accepted_at IS NULL AND revoked_at IS NULL", name: "idx_org_invitations_pending_unique"
  end
end
