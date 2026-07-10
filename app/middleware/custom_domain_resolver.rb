# frozen_string_literal: true

class CustomDomainResolver
  ENV_KEY = "windtunnel.custom_domain_organization_id"

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    host = request.host.to_s.downcase

    unless primary_host?(host)
      organization_id = Organization.find_id_by_custom_domain(host)
      env[ENV_KEY] = organization_id if organization_id
    end

    @app.call(env)
  end

  private

  def primary_host?(host)
    AppHost.primary?(host)
  end
end
