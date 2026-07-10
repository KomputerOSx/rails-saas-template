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
      render json: { url: rails_blob_url(blob, host: request.base_url) }
    rescue ActionController::ParameterMissing
      render json: { error: "Please choose an image file." }, status: :unprocessable_entity
    end
  end
end
