class EmailCampaignMailer < ApplicationMailer
  def campaign(email_campaign, user)
    @email_campaign = email_campaign

    @cid_by_signed_id = email_campaign.referenced_image_blobs_by_signed_id.transform_values do |blob|
      attachment_name = "#{blob.id}-#{blob.filename}"
      attachments.inline[attachment_name] = blob.download
      attachments[attachment_name].url
    end

    unless email_campaign.important?
      token = user.signed_id(purpose: :email_unsubscribe, expires_in: nil)
      @unsubscribe_url = email_preference_url(token)

      one_click_url = one_click_email_preference_url(token, category: email_campaign.category)
      headers["List-Unsubscribe"] = "<#{one_click_url}>"
      headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    end

    mail(to: user.email, subject: email_campaign.subject)
  end
end
