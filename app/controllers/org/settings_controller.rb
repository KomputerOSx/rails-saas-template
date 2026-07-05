module Org
  class SettingsController < BaseController
    SORT_COLUMNS    = %w[email role].freeze
    SORT_DIRECTIONS = %w[asc desc].freeze

    def index
      @sort      = params[:sort].presence_in(SORT_COLUMNS) || "email"
      @direction = params[:direction].presence_in(SORT_DIRECTIONS) || "asc"

      base = Current.organization.memberships.includes(:user, :roles)

      @memberships = case @sort
                     when "email"
                       base.joins(:user).order("users.email #{@direction.upcase}")
                     when "role"
                       role_priority = { Role::APP_OWNER => 0, Role::APP_ADMIN => 1, Role::APP_USER => 2 }
                       base.to_a.sort_by do |m|
                         pri = m.roles.map { |r| role_priority[r.name] || 99 }.min || 99
                         @direction == "asc" ? pri : -pri
                       end
                     end

      @pending_invitations = Current.organization.organization_invitations.outstanding.includes(:role, :invited_by)
    end
  end
end
