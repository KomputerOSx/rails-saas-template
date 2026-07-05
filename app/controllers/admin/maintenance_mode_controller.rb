module Admin
  class MaintenanceModeController < BaseController
    def edit
      @status = MaintenanceMode.status
    end

    def update
      enabled = params[:maintenance_mode][:enabled] == "1"
      message = params[:maintenance_mode][:message].to_s

      if enabled
        if message.blank?
          flash.now[:alert] = "Enter a message to show users before enabling maintenance mode."
          @status = { enabled: false, message: message }
          render :edit, status: :unprocessable_entity
          return
        end

        MaintenanceMode.enable!(message: message)
        log_audit(:maintenance_mode_enabled, metadata: { message: message })
      else
        MaintenanceMode.disable!
        log_audit(:maintenance_mode_disabled)
      end

      redirect_to edit_admin_maintenance_mode_path, notice: "Maintenance mode settings updated."
    end

    def force_logout_all
      sessions = Session.where.not(id: Current.session&.id)
      count = sessions.count
      sessions.destroy_all

      log_audit(:sessions_force_logged_out, metadata: { count: count })
      redirect_to edit_admin_maintenance_mode_path, notice: "Signed out #{count} other session(s)."
    end
  end
end
