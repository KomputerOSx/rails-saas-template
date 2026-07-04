class CreateTwoFactorChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :two_factor_challenges do |t|
      t.references :user, null: false, foreign_key: true
      t.string :challenge_id, null: false
      t.string :code_digest
      t.string :delivery_method, null: false, default: "email"
      t.datetime :expires_at, null: false
      t.integer :attempts, null: false, default: 0
      t.string :redirect_after
      t.string :ip_address
      t.string :user_agent
      t.datetime :used_at

      t.timestamps
    end

    add_index :two_factor_challenges, :challenge_id, unique: true
    add_index :two_factor_challenges, :delivery_method
  end
end
