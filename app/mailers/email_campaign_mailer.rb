class EmailCampaignMailer < ApplicationMailer
  def campaign(email_campaign, user)
    @email_campaign = email_campaign

    @cid_by_signed_id = email_campaign.referenced_image_blobs_by_signed_id.transform_values do |blob|
      attachment_name = "#{blob.id}-#{blob.filename}"
      attachments.inline[attachment_name] = blob.download
      attachments[attachment_name].url
    end

    mail(to: user.email, subject: email_campaign.subject)
  end
end
