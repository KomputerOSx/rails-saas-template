class CleanupExpiredSessionsJob < ApplicationJob
  queue_as :default

  def perform
    count = Session.expired.count
    Session.cleanup_expired!

    Rails.logger.info "Cleaned up #{count} expired sessions"
  end
end
