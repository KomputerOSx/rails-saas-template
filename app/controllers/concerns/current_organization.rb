module CurrentOrganization
  extend ActiveSupport::Concern

  included do
    before_action :set_current_organization
    helper_method :current_membership
  end

  private

  # The current user's Membership in Current.organization — nil if there's no current
  # organization, or (defensively) if that membership somehow holds no app-scoped role.
  def current_membership
    return nil unless Current.organization && current_user
    @current_membership ||= current_user.memberships.find_by(organization: Current.organization)
  end

  # Session-stored selection (see docs/ORGANIZATIONS_AND_RBAC.md §8): falls back to the
  # user's first organization if nothing is stored yet, or if the stored id no longer
  # refers to an org the user belongs to (e.g. they left it, or were removed).
  def set_current_organization
    return unless current_user

    organizations = current_user.organizations
    organization = organizations.find_by(id: session[:current_organization_id]) || organizations.first
    session[:current_organization_id] = organization&.id
    Current.organization = organization
  end
end
