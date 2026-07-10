# One job per campaign, not one per recipient - each recipient's send is isolated so one bad
# address can't halt the batch, and status stays a simple before/after around the loop.
class SendEmailCampaignJob < ApplicationJob
  queue_as :default

  def perform(email_campaign_id)
    campaign = EmailCampaign.find_by(id: email_campaign_id)
    return unless campaign&.sending?

    campaign.email_campaign_recipients.includes(:user).find_each do |recipient|
      begin
        EmailCampaignMailer.campaign(campaign, recipient.user).deliver_now
        recipient.mark_sent!
      rescue => e
        recipient.mark_failed!(e)
        Rails.logger.error("[SendEmailCampaignJob] failed for campaign=#{campaign.id} user=#{recipient.user_id}: #{e.message}")
      end
    end

    campaign.update!(status: :sent, sent_at: Time.current)
  end
end
