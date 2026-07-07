class RenameManagerActivationRequiredToOrgOptInRequired < ActiveRecord::Migration[8.1]
  def change
    rename_column :features, :manager_activation_required, :org_opt_in_required
  end
end
