# frozen_string_literal: true

class CustomDomainConstraint
  def self.matches?(request)
    return false if reserved_path?(request.path)

    AppHost.custom_domain?(request.host)
  end

  def self.reserved_path?(path)
    path = path.to_s
    path == "/up" || path.start_with?("/internal/")
  end
end
