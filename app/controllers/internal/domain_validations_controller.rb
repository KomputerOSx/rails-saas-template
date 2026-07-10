# frozen_string_literal: true

module Internal
  # Minimal controller for Caddy on-demand TLS ask checks. Inherits from
  # ActionController::Base (not ApplicationController) so auth, onboarding,
  # maintenance, and allow_browser filters never block certificate issuance.
  class DomainValidationsController < ActionController::Base
    skip_forgery_protection

    def show
      unless internal_request?
        return render plain: "Unauthorized", status: :unauthorized
      end

      domain = params[:domain].to_s.downcase.strip.sub(/\Awww\./, "")
      organization = Organization.find_by(custom_domain: domain)

      if organization&.custom_domain_allowed?
        render plain: "OK", status: :ok
      else
        render plain: "Not Found", status: :not_found
      end
    end

    private

    def internal_request?
      ip = request.remote_ip.to_s
      ip.start_with?("127.", "10.", "172.", "192.168.") || ip == "::1"
    end
  end
end
