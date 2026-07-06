Rails.application.config.after_initialize do
  begin
    next unless ActiveRecord::Base.connection.table_exists?(:features)

    FeatureRegistry.sync!
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished => e
    Rails.logger.warn("FeatureRegistry: skipping sync, database not ready — #{e.message}")
  end
end
