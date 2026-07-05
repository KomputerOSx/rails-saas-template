class AddOnboardingFieldsToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :onboarding_step, :string
    add_column :users, :onboarding_completed_at, :datetime

    # Don't retroactively force pre-existing accounts through the wizard.
    execute "UPDATE users SET onboarding_completed_at = created_at WHERE onboarding_completed_at IS NULL"
  end

  def down
    remove_column :users, :onboarding_completed_at
    remove_column :users, :onboarding_step
  end
end
