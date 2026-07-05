module Org
  class SettingsController < BaseController
    def index
      @memberships = Current.organization.memberships.includes(:user, :roles)
      @pending_invitations = Current.organization.organization_invitations.outstanding.includes(:role, :invited_by)
    end
  end
end
