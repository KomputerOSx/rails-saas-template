# frozen_string_literal: true

require "test_helper"

class CustomDomainDnsCheckTest < ActiveSupport::TestCase
  setup do
    @previous_host = ENV["APP_HOST"]
    @previous_ip = ENV["APP_SERVER_IP"]
    ENV["APP_HOST"] = "windtunnel.example.com"
    ENV["APP_SERVER_IP"] = "203.0.113.10"
  end

  teardown do
    ENV["APP_HOST"] = @previous_host
    ENV["APP_SERVER_IP"] = @previous_ip
  end

  test "ready when CNAME points at primary host" do
    check = CustomDomainDnsCheck.new("shop.customer.test")
    check.stub(:cname_points_to_primary?, true) do
      check.stub(:addresses_match_expected?, false) do
        result = check.call
        assert result.ready?
        assert_match(/DNS looks good/i, result.message)
      end
    end
  end

  test "ready when addresses match expected server IP" do
    check = CustomDomainDnsCheck.new("shop.customer.test")
    check.stub(:cname_points_to_primary?, false) do
      check.stub(:addresses_match_expected?, true) do
        assert check.call.ready?
      end
    end
  end

  test "pending when DNS does not point here" do
    check = CustomDomainDnsCheck.new("shop.customer.test")
    check.stub(:cname_points_to_primary?, false) do
      check.stub(:addresses_match_expected?, false) do
        result = check.call
        assert result.pending?
        assert_match(/Waiting for DNS/i, result.message)
      end
    end
  end

  test "pending when domain is blank" do
    result = CustomDomainDnsCheck.call("")
    assert result.pending?
  end
end
