module Admin
  class EmailCampaignImagesController < BaseController
    before_action { authorize :system, :manage_email_campaigns?, policy_class: SystemPolicy }

    # Formats outside ActiveStorage.content_types_allowed_inline get served as :attachment, which
    # renders as a broken <img>, not a download - e.g. HEIC photos from iPhones would silently fail.
    ALLOWED_CONTENT_TYPES = ActiveStorage.web_image_content_types

    # Images are sent as inline (CID) attachments, not fetched URLs (see EmailCampaignMailer) - so
    # every uploaded byte gets multiplied by recipient count at send time. Capped well below
    # EmailCampaign::MAX_TOTAL_INLINE_IMAGE_BYTES so one oversized upload can't eat the whole budget.
    MAX_FILE_SIZE = 5.megabytes

    def create
      file = params.require(:file)
      unless ALLOWED_CONTENT_TYPES.include?(file.content_type.to_s)
        return render json: { error: "Please upload a PNG, JPEG, GIF, or WebP image." }, status: :unprocessable_entity
      end
      if file.size > MAX_FILE_SIZE
        return render json: { error: "Image must be smaller than #{MAX_FILE_SIZE / 1.megabyte} MB." }, status: :unprocessable_entity
      end

      blob = ActiveStorage::Blob.create_and_upload!(
        io: file.to_io,
        filename: file.original_filename,
        content_type: file.content_type
      )
      # Anchored to config.action_mailer.default_url_options, not request.base_url - the admin's
      # browsing host (localhost, an internal IP) means nothing to an external email recipient.
      render json: { url: rails_blob_url(blob, **Rails.application.config.action_mailer.default_url_options) }
    rescue ActionController::ParameterMissing
      render json: { error: "Please choose an image file." }, status: :unprocessable_entity
    end
  end
end
