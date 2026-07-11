class EmailCampaignMailer < ApplicationMailer
  # Embeds body_html's images as inline (CID) attachments instead of linking to a
  # rails_blob_url the recipient's mail client would have to fetch over the public internet -
  # see docs/plans/email-campaigns.md #7 for why the URL-based approach never reliably worked.
  def campaign(email_campaign, user)
    @email_campaign = email_campaign

    @cid_by_signed_id = email_campaign.referenced_image_blobs_by_signed_id.transform_values do |blob|
      # Prefixed with blob.id - two different blobs can share an original filename (e.g. two
      # separately-uploaded "logo.png"s), which would otherwise clobber one inline attachment.
      attachment_name = "#{blob.id}-#{blob.filename}"
      attachments.inline[attachment_name] = blob.download
      attachments[attachment_name].url
    end

    mail(to: user.email, subject: email_campaign.subject)
  end
end
