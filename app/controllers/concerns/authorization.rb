module Authorization
  extend ActiveSupport::Concern

  class_methods do
    def require_admin(**options)
      before_action :require_admin!, **options
    end
  end

  private

  def require_admin!
    return if current_user&.admin?

    redirect_to root_path, alert: "You are not authorized to access this page."
  end
end
