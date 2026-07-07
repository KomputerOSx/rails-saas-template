Rails.application.config.after_initialize do
  begin
    next unless ActiveRecord::Base.connection.table_exists?(:permissions) &&
                ActiveRecord::Base.connection.table_exists?(:roles) &&
                ActiveRecord::Base.connection.table_exists?(:role_permissions)

    RbacRegistry.sync!
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished => e
    Rails.logger.warn("RbacRegistry: skipping sync, database not ready - #{e.message}")
  end
end
