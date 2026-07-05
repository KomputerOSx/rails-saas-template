class User < ApplicationRecord
  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :password_histories, dependent: :destroy
  has_many :password_reset_tokens, dependent: :destroy
  has_many :two_factor_challenges, dependent: :destroy
  has_many :audit_logs, dependent: :nullify
  has_many :user_roles, dependent: :destroy
  has_many :granted_user_roles, class_name: "UserRole", foreign_key: :granted_by_id, dependent: :nullify
  has_many :roles, through: :user_roles
  has_many :memberships, dependent: :destroy
  has_many :organizations, through: :memberships
  has_many :granted_membership_roles, class_name: "MembershipRole", foreign_key: :granted_by_id, dependent: :nullify
  has_many :notification_recipients, dependent: :destroy
  has_many :notifications, through: :notification_recipients
  has_many :created_notifications, class_name: "Notification", foreign_key: :created_by_id, dependent: :nullify
  has_many :sent_invitations, class_name: "OrganizationInvitation", foreign_key: :invited_by_id, dependent: :nullify
  has_many :identities, dependent: :destroy

  MIN_PASSWORD_LENGTH = 8
  PASSWORD_HISTORY_LIMIT = 10
  MAX_LOGIN_ATTEMPTS = 5
  LOCKOUT_DURATION = 30.minutes
  CONFIRMATION_EXPIRY = 30.minutes
  EMAIL_CHANGE_EXPIRY = 30.minutes
  MAX_EMAIL_CHANGE_ATTEMPTS = 5
  TOTP_ISSUER = Rails.application.class.module_parent_name
  ACCOUNT_DELETION_CODE_EXPIRY = 30.minutes

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }

  validates :password,
    length: { minimum: MIN_PASSWORD_LENGTH, message: "must be at least #{MIN_PASSWORD_LENGTH} characters" },
    format: {
      with: /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d).*\z/,
      message: "must include at least one lowercase letter, one uppercase letter, and one digit"
    },
    if: :password_digest_changed?

  validate :password_not_common, if: :password_digest_changed?
  validate :password_no_sequential_patterns, if: :password_digest_changed?
  validate :password_no_repeated_characters, if: :password_digest_changed?
  validate :password_no_keyboard_patterns, if: :password_digest_changed?
  validate :password_not_in_history, if: :password_digest_changed?
  validate :clear_password_blank_error_for_oauth_users

  after_update :save_password_to_history, if: :saved_change_to_password_digest?

  # --- Account lockout ---

  def locked?
    locked_until.present? && locked_until > Time.current
  end

  def increment_failed_login!
    self.failed_login_attempts += 1

    if failed_login_attempts >= MAX_LOGIN_ATTEMPTS
      self.locked_until = LOCKOUT_DURATION.from_now
      AuditLog.create!(user: self, event_type: :account_locked, ip_address: Current.ip_address,
        user_agent: Current.user_agent, metadata: { reason: "max_failed_attempts", attempts: failed_login_attempts })
    end

    save!
  end

  def reset_failed_login!
    update!(failed_login_attempts: 0, locked_until: nil)
  end

  def unlock!
    update!(failed_login_attempts: 0, locked_until: nil)
    AuditLog.create!(user: self, event_type: :account_unlocked, ip_address: Current.ip_address, user_agent: Current.user_agent)
  end

  # --- Disable (admin-initiated, permanent until re-enabled) ---

  def disabled?
    disabled_at.present?
  end

  def disable!
    update!(disabled_at: Time.current)
    sessions.destroy_all
  end

  def enable!
    update!(disabled_at: nil)
  end

  # --- RBAC ---

  def has_role?(name, scope: nil)
    scoped = scope ? roles.where(scope: scope.to_s) : roles
    scoped.exists?(name: name.to_s)
  end

  def has_permission?(key, organization: nil)
    if organization
      memberships.find_by(organization: organization)&.has_permission?(key) || false
    else
      roles.joins(:permissions).exists?(permissions: { key: key.to_s })
    end
  end

  def system_admin?
    has_role?(Role::SYSTEM_ADMIN, scope: :system)
  end

  def unread_notification_count
    notification_recipients.inbox.unread.count
  end

  def grant_role!(role, granted_by: nil)
    user_roles.find_or_create_by!(role: role) { |user_role| user_role.granted_by = granted_by }
  end

  def revoke_role!(role)
    user_roles.find_by(role: role)&.destroy
  end

  # --- Email confirmation (6-digit code, not a link) ---

  def self.generate_code
    format("%06d", SecureRandom.random_number(1_000_000))
  end

  def self.digest_code(code)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, code.to_s)
  end

  def confirmed?
    confirmed_at.present?
  end

  # --- Onboarding ---

  def onboarding_completed?
    onboarding_completed_at.present?
  end

  def onboarding_current_step
    Onboarding.find(onboarding_step) || Onboarding.first_step
  end

  # --- Email change (requires a code confirmed from both the old and new address) ---

  def email_change_pending?
    unconfirmed_email.present?
  end

  def email_change_expired?
    email_change_requested_at.blank? || email_change_requested_at < EMAIL_CHANGE_EXPIRY.ago
  end

  def email_change_old_confirmed?
    email_change_old_confirmed_at.present?
  end

  def email_change_fully_confirmed?
    email_change_old_confirmed_at.present? && email_change_new_confirmed_at.present?
  end

  # Step 1: stash the requested new address and send a code to the CURRENT (old) address.
  # Does not touch `email` itself — only takes effect once both sides confirm. Returns the
  # raw code (for the mailer) or nil if validation failed (see #errors).
  def request_email_change!(new_email)
    new_email = new_email.to_s.strip.downcase
    return nil if new_email.blank? || new_email == email

    unless new_email.match?(URI::MailTo::EMAIL_REGEXP)
      errors.add(:email, "is invalid")
      return nil
    end

    if self.class.where(email: new_email).where.not(id: id).exists?
      errors.add(:email, "is already taken")
      return nil
    end

    self.class.generate_code.tap do |code|
      update!(
        unconfirmed_email: new_email,
        email_change_old_code_digest: self.class.digest_code(code),
        email_change_new_code_digest: nil,
        email_change_requested_at: Time.current,
        email_change_old_confirmed_at: nil,
        email_change_new_confirmed_at: nil,
        email_change_attempts: 0
      )
    end
  end

  # Step 2: verify the code sent to the OLD address. On success, generates and returns the
  # code to send to the NEW address (mailer sends it); on failure returns nil (see #errors).
  def confirm_email_change_old!(code)
    return :expired if email_change_expired?
    return :locked if email_change_attempts >= MAX_EMAIL_CHANGE_ATTEMPTS

    unless ActiveSupport::SecurityUtils.secure_compare(self.class.digest_code(code.to_s), email_change_old_code_digest.to_s)
      increment!(:email_change_attempts)
      return :invalid
    end

    self.class.generate_code.tap do |new_code|
      update!(
        email_change_old_confirmed_at: Time.current,
        email_change_old_code_digest: nil,
        email_change_new_code_digest: self.class.digest_code(new_code),
        email_change_attempts: 0
      )
    end
  end

  # Step 3: verify the code sent to the NEW address. Finalizes the swap on success.
  # Returns :completed, :expired, :locked, or :invalid.
  def confirm_email_change_new!(code)
    return :expired if email_change_expired?
    return :locked if email_change_attempts >= MAX_EMAIL_CHANGE_ATTEMPTS

    if ActiveSupport::SecurityUtils.secure_compare(self.class.digest_code(code.to_s), email_change_new_code_digest.to_s)
      finalize_email_change!
      :completed
    else
      increment!(:email_change_attempts)
      :invalid
    end
  end

  def finalize_email_change!
    update!(
      email: unconfirmed_email,
      unconfirmed_email: nil,
      email_change_old_code_digest: nil,
      email_change_new_code_digest: nil,
      email_change_requested_at: nil,
      email_change_old_confirmed_at: nil,
      email_change_new_confirmed_at: nil,
      email_change_attempts: 0
    )
  end

  def cancel_email_change!
    update_columns(
      unconfirmed_email: nil,
      email_change_old_code_digest: nil,
      email_change_new_code_digest: nil,
      email_change_requested_at: nil,
      email_change_old_confirmed_at: nil,
      email_change_new_confirmed_at: nil,
      email_change_attempts: 0
    )
  end

  # --- Account deletion confirmation ---

  def request_account_deletion_code!
    code = self.class.generate_code
    update_columns(
      account_deletion_code_digest: self.class.digest_code(code),
      account_deletion_code_sent_at: Time.current
    )
    code
  end

  def verify_account_deletion_code!(code)
    return false if account_deletion_code_sent_at.nil?
    return false if account_deletion_code_sent_at < ACCOUNT_DELETION_CODE_EXPIRY.ago
    ActiveSupport::SecurityUtils.secure_compare(
      self.class.digest_code(code.to_s),
      account_deletion_code_digest.to_s
    )
  end

  # --- TOTP (two-factor authentication) ---

  def totp_enabled?
    totp_secret.present? && totp_enabled_at.present?
  end

  def self.generate_totp_secret
    ROTP::Base32.random_base32
  end

  def totp_provisioning_uri(secret = totp_secret)
    ROTP::TOTP.new(secret, issuer: TOTP_ISSUER).provisioning_uri(email)
  end

  # Used during enrollment: no side effects, checks a not-yet-persisted secret.
  def valid_totp_code?(code, secret = totp_secret)
    self.class.verify_totp_code(secret, code).present?
  end

  # Used during login: mutates totp_last_used_at for replay protection.
  def verify_totp!(code)
    return false unless totp_enabled?

    verified_at = self.class.verify_totp_code(totp_secret, code, after: totp_last_used_at)
    return false unless verified_at

    update!(totp_last_used_at: verified_at)
    true
  end

  def enable_totp!(secret)
    update!(totp_secret: secret, totp_enabled_at: Time.current, totp_last_used_at: nil)
  end

  def disable_totp!
    update!(totp_secret: nil, totp_enabled_at: nil, totp_last_used_at: nil)
  end

  def self.verify_totp_code(secret, code, after: nil)
    submitted = code.to_s.gsub(/\s+/, "")
    return nil unless secret.present? && submitted.match?(/\A\d{6}\z/)

    ROTP::TOTP.new(secret).verify(submitted, drift_behind: 30, drift_ahead: 30, after: after)
  end

  private

  # --- Password security pattern detection ---

  def password_not_common
    return unless password.present?

    common_passwords = %w[
      password password123 12345678 qwerty123 admin123
      welcome1 letmein1 Password1 Qwerty123 Admin123
      pass123 passw0rd Passw0rd Welcome123
    ]

    if common_passwords.any? { |cp| password.downcase == cp.downcase }
      errors.add(:password, "is too common. Please choose a more unique password.")
      return
    end

    common_words = %w[password pass admin welcome letmein]
    if common_words.any? { |word| password.downcase.include?(word) }
      errors.add(:password, "contains common words. Please choose a more unique password.")
    end
  end

  def password_no_sequential_patterns
    return unless password.present?

    password_lower = password.downcase

    if password_lower =~ /012|123|234|345|456|567|678|789|890/
      errors.add(:password, "contains sequential numbers (e.g., 123, 456). Please avoid sequential patterns.")
      return
    end

    if password_lower =~ /abc|bcd|cde|def|efg|fgh|ghi|hij|ijk|jkl|klm|lmn|mno|nop|opq|pqr|qrs|rst|stu|tuv|uvw|vwx|wxy|xyz/
      errors.add(:password, "contains sequential letters (e.g., abc, xyz). Please avoid sequential patterns.")
      return
    end

    if password_lower =~ /987|876|765|654|543|432|321|210/
      errors.add(:password, "contains reverse sequential numbers. Please avoid sequential patterns.")
    end
  end

  def password_no_repeated_characters
    return unless password.present?

    if password =~ /(.)\1{2,}/
      errors.add(:password, "contains repeated characters (e.g., 111, aaa). Please use more variety.")
    end
  end

  def password_no_keyboard_patterns
    return unless password.present?

    password_lower = password.downcase

    keyboard_patterns = %w[
      qwerty qwertyui asdfgh asdfghjk zxcvbn zxcvbnm
      qwert asdf zxcv 1qaz 2wsx
      !qaz @wsx
    ]

    keyboard_patterns.each do |pattern|
      if password_lower.include?(pattern)
        errors.add(:password, "contains keyboard patterns (e.g., qwerty, asdf). Please avoid keyboard sequences.")
        return
      end
    end
  end

  def password_not_in_history
    return unless password.present?
    return if new_record? && password_histories.empty?

    if PasswordHistory.password_used_before?(self, password)
      errors.add(:password, "has been used recently. Please choose a different password (last #{PASSWORD_HISTORY_LIMIT} passwords are tracked).")
    end
  end

  def save_password_to_history
    old_digest = password_digest_before_last_save || password_digest
    password_histories.create!(password_digest: old_digest)

    old_passwords = password_histories.order(created_at: :desc).offset(PASSWORD_HISTORY_LIMIT)
    PasswordHistory.where(id: old_passwords.pluck(:id)).destroy_all
  end

  def clear_password_blank_error_for_oauth_users
    errors.delete(:password, :blank) if persisted? && !password_digest_changed?
  end
end
