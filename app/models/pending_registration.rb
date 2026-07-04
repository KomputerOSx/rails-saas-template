# Holds a not-yet-created account between "signed up" and "entered the confirmation
# code" — backed by Rails.cache (not the database) so no `users` row exists, and no
# unique-email conflict is possible, until the code is actually confirmed. Auto-expires
# via the cache TTL; brute-forcing the code is mitigated at the Rack::Attack layer
# (config/initializers/rack_attack.rb), not by per-record attempt tracking here.
class PendingRegistration
  EXPIRY = User::CONFIRMATION_EXPIRY

  attr_reader :email, :password_digest, :code_digest

  def self.cache_key(email)
    "pending_registration:#{email}"
  end

  # Returns the raw 6-digit code (for the mailer). Re-signing-up with an email that
  # already has a pending registration simply overwrites it with a fresh code.
  def self.create!(email:, password_digest:)
    code = User.generate_code
    data = { email: email, password_digest: password_digest, code_digest: User.digest_code(code) }
    Rails.cache.write(cache_key(email), data, expires_in: EXPIRY)
    code
  end

  def self.find(email)
    return nil if email.blank?

    data = Rails.cache.read(cache_key(email))
    data ? new(data) : nil
  end

  def self.destroy(email)
    Rails.cache.delete(cache_key(email))
  end

  def initialize(data)
    @email = data[:email]
    @password_digest = data[:password_digest]
    @code_digest = data[:code_digest]
  end

  def verify_code(code)
    ActiveSupport::SecurityUtils.secure_compare(User.digest_code(code.to_s), code_digest.to_s)
  end
end
