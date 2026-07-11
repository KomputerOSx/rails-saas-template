class EmailCampaign < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :email_campaign_recipients, dependent: :destroy
  has_many :recipients, through: :email_campaign_recipients, source: :user

  MAX_WIDTHS = { narrow: 480, standard: 600, wide: 720 }.freeze
  HEX_COLOR_REGEX = /\A#[0-9a-fA-F]{6}\z/

  # Images are sent as inline (CID) attachments (see EmailCampaignMailer), so their raw bytes go
  # out with every recipient's copy. Budgeted well under the Azure SMTP relay's 10 MB message cap
  # to leave headroom for base64's ~33% inflation plus the HTML/MIME overhead around them.
  MAX_TOTAL_INLINE_IMAGE_BYTES = 6.megabytes

  validates :subject, presence: true
  validates :body_html, presence: true
  validates :max_width, inclusion: { in: MAX_WIDTHS.values }
  validates :bg_color, format: { with: HEX_COLOR_REGEX }

  enum :status, { draft: "draft", sending: "sending", sent: "sent" }, default: "draft"

  scope :recent, -> { order(created_at: :desc) }

  before_save :sanitize_body_html

  ALLOWED_TAGS = %w[p br strong em u a ul ol li h1 h2 h3 blockquote span img].freeze
  ALLOWED_ATTRIBUTES = %w[href style src alt width].freeze

  BLOB_REDIRECT_URL_REGEX = %r{https?://[^\s"']*/rails/active_storage/blobs/redirect/([^/\s"']+)/[^\s"']*}

  # Snapshots recipients but sends nothing - sending is a deliberate separate step (see #deliver).
  def self.create_draft!(subject:, body_html:, to:, created_by: nil, max_width: nil, bg_color: nil)
    recipients = Array(to.respond_to?(:find_each) ? to.to_a : to).uniq
    raise ArgumentError, "no recipients given" if recipients.empty?

    attrs = { subject: subject, body_html: body_html, created_by: created_by }
    attrs[:max_width] = max_width if max_width.present?
    attrs[:bg_color] = bg_color if bg_color.present?

    transaction do
      campaign = create!(attrs)
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

  def referenced_image_blobs_by_signed_id
    body_html.to_s.scan(BLOB_REDIRECT_URL_REGEX).flatten.uniq.each_with_object({}) do |signed_id, blobs|
      blob = ActiveStorage::Blob.find_signed(signed_id)
      blobs[signed_id] = blob if blob
    end
  end

  def referenced_image_blobs
    referenced_image_blobs_by_signed_id.values
  end

  def referenced_images_total_bytes
    referenced_image_blobs.sum(&:byte_size)
  end

  def images_too_large_to_send?
    referenced_images_total_bytes > MAX_TOTAL_INLINE_IMAGE_BYTES
  end

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
