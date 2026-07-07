class AddOverMemberLimitAtToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :over_member_limit_at, :datetime
  end
end
