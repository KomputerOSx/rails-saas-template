# frozen_string_literal: true

require "resolv"

# Checks whether a custom domain's public DNS points at this app
# (CNAME → APP_HOST, or A/AAAA → APP_SERVER_IP / same addresses as APP_HOST).
class CustomDomainDnsCheck
  Result = Data.define(:status, :message) do
    def ready? = status == :ready
    def pending? = status == :pending
    def as_json(*) = { status: status.to_s, message: message }
  end

  def self.call(domain)
    new(domain).call
  end

  def initialize(domain)
    @domain = AppHost.normalize(domain)
  end

  def call
    return Result.new(status: :pending, message: "No domain configured.") if @domain.blank?

    if cname_points_to_primary? || addresses_match_expected?
      Result.new(status: :ready, message: "DNS looks good. SSL will issue on the first HTTPS visit.")
    else
      Result.new(status: :pending, message: "Waiting for DNS — add the CNAME or A record below, then wait for it to propagate.")
    end
  rescue Resolv::ResolvError, Errno::ECONNREFUSED, SocketError => e
    Result.new(status: :pending, message: "Could not resolve DNS yet (#{e.class.name}).")
  end

  private

  def cname_points_to_primary?
    primary = AppHost.normalize(AppHost.primary_host)
    return false if primary.blank?

    Resolv::DNS.open do |dns|
      dns.timeouts = 2
      records = dns.getresources(@domain, Resolv::DNS::Resource::IN::CNAME)
      records.any? { |record| AppHost.normalize(record.name.to_s) == primary }
    end
  end

  def addresses_match_expected?
    expected = expected_addresses
    return false if expected.empty?

    actual = Resolv.getaddresses(@domain).map { |ip| ip.to_s.downcase }
    (actual & expected).any?
  end

  def expected_addresses
    addresses = []

    begin
      addresses.concat(Resolv.getaddresses(AppHost.primary_host)) if AppHost.primary_host.present?
    rescue Resolv::ResolvError, SocketError
      # Primary host may not resolve in test/dev — fall through to APP_SERVER_IP.
    end

    server_ip = AppHost.server_ip
    addresses << server_ip if server_ip.present? && server_ip != "YOUR_SERVER_IP"
    addresses.map { |ip| ip.to_s.downcase }.uniq
  end
end
