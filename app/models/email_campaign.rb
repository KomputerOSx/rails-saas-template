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

  # Matches the <img src="..."> shape EmailCampaignImagesController's rails_blob_url produces,
  # capturing the signed_id - how the mailer finds which blobs to inline (see #referenced_image_blobs)
  # and where to rewrite src="..." to a cid: reference (see #body_html_with_cid_images).
  BLOB_REDIRECT_URL_REGEX = %r{https?://[^\s"']*/rails/active_storage/blobs/redirect/([^/\s"']+)/[^\s"']*}

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

  # Resolves body_html's <img src="...blobs/redirect/:signed_id/..."> references back to their
  # ActiveStorage::Blob records, keyed by the signed_id substring embedded in each URL. This is what
  # EmailCampaignMailer loops to build inline (CID) attachments - only the images a campaign actually
  # uses, not every image ever uploaded via the unattached-blob upload flow.
  def referenced_image_blobs_by_signed_id
    body_html.to_s.scan(BLOB_REDIRECT_URL_REGEX).flatten.uniq.each_with_object({}) do |signed_id, blobs|
      blob = ActiveStorage::Blob.find_signed(signed_id)
      blobs[signed_id] = blob if blob
    end
  end

  def referenced_image_blobs
    referenced_image_blobs_by_signed_id.values
  end

  # Rewrites body_html's blob-redirect image URLs to the cid: references the mailer's inline
  # attachments produced, keyed by the same signed_id BLOB_REDIRECT_URL_REGEX captures. Only
  # meaningful inside an actual MIME email - the admin-facing `show` preview renders body_html as-is.
  def body_html_with_cid_images(cid_by_signed_id)
    body_html.to_s.gsub(BLOB_REDIRECT_URL_REGEX) { cid_by_signed_id[$1] || $& }
  end

  private

  # Single sanitization point - the mailer view renders body_html with `raw`, trusting this ran.
  def sanitize_body_html
    self.body_html = ActionController::Base.helpers.sanitize(
      body_html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES
    )
  end
end
