class EmailCampaignMailer < ApplicationMailer
  def campaign(email_campaign, user)
    @email_campaign = email_campaign

    mail(to: user.email, subject: email_campaign.subject)
  end
end
