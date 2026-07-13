# frozen_string_literal: true

module Org
  class CustomDomainsController < BaseController
    def create
      authorize Current.organization, :update?

      unless Current.organization.custom_domain_allowed?
        return redirect_to org_settings_path, alert: "Custom domains require the Growth plan."
      end

      if Current.organization.update(custom_domain: custom_domain_param)
        log_audit(:custom_domain_updated, resource: Current.organization, metadata: { custom_domain: Current.organization.custom_domain })
        redirect_to org_settings_path, notice: "Custom domain saved. Add a DNS record to finish setup."
      else
        redirect_to org_settings_path, alert: Current.organization.errors.full_messages.to_sentence
      end
    end

    def destroy
      authorize Current.organization, :update?

      Current.organization.update!(custom_domain: nil)
      log_audit(:custom_domain_removed, resource: Current.organization)
      redirect_to org_settings_path, notice: "Custom domain removed."
    end

    def status
      skip_authorization # same visibility as org settings - any org member

      unless Current.organization.custom_domain.present?
        return render json: { status: "pending", message: "No domain configured." }
      end

      result = CustomDomainDnsCheck.call(Current.organization.custom_domain)
      render json: result
    end

    private

    def custom_domain_param
      params.require(:organization).permit(:custom_domain)[:custom_domain]
    end
  end
end
