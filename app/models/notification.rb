class Notification < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :notification_recipients, dependent: :destroy
  has_many :recipients, through: :notification_recipients, source: :user

  validates :title, presence: true
  validates :body, presence: true

  scope :active, -> { where(withdrawn_at: nil) }
  scope :withdrawn, -> { where.not(withdrawn_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def self.deliver!(title:, body:, to:, created_by: nil)
    recipients = Array(to.respond_to?(:find_each) ? to.to_a : to).uniq
    raise ArgumentError, "no recipients given" if recipients.empty?

    transaction do
      notification = create!(title: title, body: body, created_by: created_by)
      recipients.each { |user| notification.notification_recipients.create!(user: user) }
      notification
    end
  end

  def withdrawn?
    withdrawn_at.present?
  end

  def withdraw!
    update!(withdrawn_at: Time.current)
  end
end
