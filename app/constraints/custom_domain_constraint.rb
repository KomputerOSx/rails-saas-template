# frozen_string_literal: true

class CustomDomainConstraint
  def self.matches?(request)
    AppHost.custom_domain?(request.host)
  end
end
