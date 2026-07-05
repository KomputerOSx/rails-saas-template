module MaintenanceGate
  extend ActiveSupport::Concern

  included do
    before_action :enforce_maintenance_mode!
  end

  private

  def enforce_maintenance_mode!
    return if controller_path.start_with?("admin/")
    return if current_user&.system_admin?

    status = MaintenanceMode.status
    return unless status[:enabled]

    render template: "maintenance/index", layout: "auth", status: :service_unavailable,
      locals: { message: status[:message] }
  end
end
