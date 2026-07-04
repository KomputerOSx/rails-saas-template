class PasswordResetToken < ApplicationRecord
  EXPIRY = 10.minutes
  TOKEN_BYTES = 32

  belongs_to :user

  scope :active, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  validates :token_digest, presence: true, uniqueness: true
  validates :password_digest_snapshot, presence: true
  validates :expires_at, presence: true

  def self.generate_for!(user, request_ip:, request_user_agent:)
    raw_token = SecureRandom.urlsafe_base64(TOKEN_BYTES)

    transaction do
      user.password_reset_tokens.active.update_all(used_at: Time.current, updated_at: Time.current)

      record = user.password_reset_tokens.create!(
        token_digest: digest(raw_token),
        password_digest_snapshot: user.password_digest,
        expires_at: EXPIRY.from_now,
        request_ip: request_ip,
        request_user_agent: request_user_agent
      )

      [ record, raw_token ]
    end
  end

  def self.find_usable(raw_token)
    return nil if raw_token.blank?

    active.includes(:user).find_by(token_digest: digest(raw_token.to_s))
  end

  def self.digest(raw_token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, raw_token.to_s)
  end

  # Invalidates a stale reset link if the password was changed some other way
  # (e.g. from the password-change form) between the reset request and its use.
  def password_still_matches?
    ActiveSupport::SecurityUtils.secure_compare(password_digest_snapshot.to_s, user.password_digest.to_s)
  rescue ArgumentError
    false
  end

  def usable?
    used_at.blank? && expires_at.future? && password_still_matches?
  end

  def consume!
    update!(used_at: Time.current)
  end
end
