module Admin
  class EmailCampaignImagesController < BaseController
    before_action { authorize :system, :manage_email_campaigns?, policy_class: SystemPolicy }

    # ActiveStorage only serves a curated set of formats with Content-Disposition: inline (see
    # ActiveStorage.content_types_allowed_inline) - anything else gets forced to :attachment, which
    # browsers/mail clients refuse to render as <img> (a broken-image icon, not a download prompt,
    # since the request is coming from an <img src>). image/* alone let through formats like HEIC
    # (common for iPhone photos) or SVG that either aren't inline-served or aren't renderable as a
    # plain <img> everywhere - restrict to the exact set Rails itself curates as web-safe.
    ALLOWED_CONTENT_TYPES = ActiveStorage.web_image_content_types

    def create
      file = params.require(:file)
      unless ALLOWED_CONTENT_TYPES.include?(file.content_type.to_s)
        return render json: { error: "Please upload a PNG, JPEG, GIF, or WebP image." }, status: :unprocessable_entity
      end

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
