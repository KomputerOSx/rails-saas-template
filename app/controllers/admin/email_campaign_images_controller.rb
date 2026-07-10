module Admin
  class EmailCampaignImagesController < BaseController
    before_action { authorize :system, :manage_email_campaigns?, policy_class: SystemPolicy }

    def create
      file = params.require(:file)
      raise ActionController::ParameterMissing, :file unless file.content_type.to_s.start_with?("image/")

      blob = ActiveStorage::Blob.create_and_upload!(
        io: file.to_io,
        filename: file.original_filename,
        content_type: file.content_type
      )
      # Anchored to the same host every other mailer link in this app already uses
      # (config.action_mailer.default_url_options), not request.base_url - the admin composing a
      # campaign might be browsing via an internal IP/localhost/VPN host that's meaningless to an
      # external email recipient, so the embedded image URL can't depend on that.
      render json: { url: rails_blob_url(blob, **Rails.application.config.action_mailer.default_url_options) }
    rescue ActionController::ParameterMissing
      render json: { error: "Please choose an image file." }, status: :unprocessable_entity
    end
  end
end
