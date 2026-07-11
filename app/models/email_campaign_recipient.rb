class EmailCampaignRecipient < ApplicationRecord
  belongs_to :email_campaign
  belongs_to :user

  validates :user_id, uniqueness: { scope: :email_campaign_id }

  scope :pending, -> { where(sent_at: nil, failed_at: nil, skipped_at: nil) }
  scope :sent, -> { where.not(sent_at: nil) }
  scope :failed, -> { where.not(failed_at: nil) }
  scope :skipped, -> { where.not(skipped_at: nil) }

  def mark_sent!
    update!(sent_at: Time.current, failed_at: nil, skipped_at: nil, error_message: nil)
  end

  def mark_failed!(error)
    update!(failed_at: Time.current, error_message: error.to_s.truncate(500))
  end

  # Recipient had opted out of this campaign's category - not attempted, not a failure.
  def mark_skipped!
    update!(skipped_at: Time.current, sent_at: nil, failed_at: nil, error_message: nil)
  end
end
