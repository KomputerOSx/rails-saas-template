class EmailCampaign < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :email_campaign_recipients, dependent: :destroy
  has_many :recipients, through: :email_campaign_recipients, source: :user

  validates :subject, presence: true
  validates :body_html, presence: true

  enum :status, { draft: "draft", sending: "sending", sent: "sent" }, default: "draft"

  scope :recent, -> { order(created_at: :desc) }

  before_save :sanitize_body_html

  ALLOWED_TAGS = %w[p br strong em u a ul ol li h1 h2 h3 blockquote].freeze
  ALLOWED_ATTRIBUTES = %w[href].freeze

  # Persists the campaign and snapshots its recipient list, but sends nothing - sending is a
  # deliberate separate step (#deliver on the controller) since email, unlike Notification, can't
  # be withdrawn after the fact.
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

  private

  # Single sanitization point - the mailer view renders body_html with `raw` on the assumption
  # it was already cleaned here, once, at write time. Allow-list mirrors the editor's enabled
  # formatting (see RichTextEditorController's StarterKit config) so nothing a user can type gets
  # silently stripped on save.
  def sanitize_body_html
    self.body_html = ActionController::Base.helpers.sanitize(
      body_html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES
    )
  end
end
