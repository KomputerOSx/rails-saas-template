class EmailCampaign < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :email_campaign_recipients, dependent: :destroy
  has_many :recipients, through: :email_campaign_recipients, source: :user

  validates :subject, presence: true
  validates :body_html, presence: true

  enum :status, { draft: "draft", sending: "sending", sent: "sent" }, default: "draft"

  scope :recent, -> { order(created_at: :desc) }

  before_save :sanitize_body_html

  ALLOWED_TAGS = %w[p br strong em u a ul ol li h1 h2 h3 blockquote span img].freeze
  ALLOWED_ATTRIBUTES = %w[href style src alt width].freeze

  # Snapshots recipients but sends nothing - sending is a deliberate separate step (see #deliver).
  def self.create_draft!(subject:, body_html:, to:, created_by: nil)
    recipients = Array(to.respond_to?(:find_each) ? to.to_a : to).uniq
    raise ArgumentError, "no recipients given" if recipients.empty?

    transaction do
      campaign = create!(subject: subject, body_html: body_html, created_by: created_by)
      recipients.each { |user| campaign.email_campaign_recipients.create!(user: user) }
      campaign
    end
  end

  def deliverable?
    draft?
  end

  # .sent/.failed/.pending are EmailCampaignRecipient's scopes, not this class's status enum scope.
  def recipient_counts
    scope = email_campaign_recipients
    { total: scope.count, sent: scope.sent.count, failed: scope.failed.count, pending: scope.pending.count }
  end

  private

  # Single sanitization point - the mailer view renders body_html with `raw`, trusting this ran.
  def sanitize_body_html
    self.body_html = ActionController::Base.helpers.sanitize(
      body_html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES
    )
  end
end
