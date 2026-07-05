module CurrentOrganization
  extend ActiveSupport::Concern

  included do
    before_action :set_current_organization
  end

  private

  # Every user has exactly one Organization until invites create more (see
  # docs/ORGANIZATIONS_AND_RBAC.md) — `.first` is unambiguous today and isolates the
  # one lookup that changes when real multi-org switching is built later.
  def set_current_organization
    Current.organization = current_user&.organizations&.first
  end
end
