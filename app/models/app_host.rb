# frozen_string_literal: true

# Primary application hostname(s) vs customer custom domains.
module AppHost
  module_function

  # Host Authorization may pass "shop.acme.test:3000"; strip port + www.
  def normalize(host)
    host.to_s.downcase.split(":", 2).first.to_s.sub(/\Awww\./, "")
  end

  def primary_hosts
    hosts = [ ENV["APP_HOST"].presence, "localhost", "127.0.0.1" ].compact
    # Rails integration tests default to www.example.com / example.com.
    hosts.concat(%w[example.com www.example.com]) if defined?(Rails) && (Rails.env.test? || Rails.env.development?)
    hosts.map { |host| normalize(host) }.uniq
  end

  def primary?(host)
    normalized = normalize(host)
    return true if primary_hosts.include?(normalized)

    # Development / test default when APP_HOST is unset: treat www.example.com style
    # fixture hosts as primary only when they match the configured host list.
    primary_hosts.any? { |primary| normalized == primary || normalized.end_with?(".#{primary}") }
  end

  def custom_domain?(host)
    !primary?(host)
  end

  # Used by config.hosts in development/production.
  def allowed_request_host?(host)
    normalized = normalize(host)
    primary?(normalized) || Organization.exists?(custom_domain: normalized)
  end

  def primary_host
    ENV["APP_HOST"].presence || "localhost"
  end

  def server_ip
    ENV["APP_SERVER_IP"].presence || "YOUR_SERVER_IP"
  end
end
