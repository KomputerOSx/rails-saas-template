# Authentication & Security Architecture — RxTerminal

A complete reference for the authentication, authorization, 2FA, password-strength, and
security-hardening systems built in this app, written so the whole system can be ported into
a fresh Rails 8 project. All code below is copied verbatim from the current codebase (paths
noted above each block) — treat this file as a snapshot in time, not a substitute for reading
the live source if it has since changed.

## Contents

1. [Overview & architecture](#1-overview--architecture)
2. [Gems required](#2-gems-required)
3. [Database schema](#3-database-schema)
4. [Core session authentication (staff/manager/admin)](#4-core-session-authentication-staffmanageradmin)
5. [Two-factor authentication (TOTP + email fallback)](#5-two-factor-authentication-totp--email-fallback)
6. [Password strength & lifecycle](#6-password-strength--lifecycle)
7. [Password reset ("forgot password")](#7-password-reset-forgot-password)
8. [The `/profile` route](#8-the-profile-route)
9. [Role-based access control (RBAC) & multi-tenant org selection](#9-role-based-access-control-rbac--multi-tenant-org-selection)
10. [Kiosk device authentication (JWT)](#10-kiosk-device-authentication-jwt)
11. [Waiting-display dual-mode authentication](#11-waiting-display-dual-mode-authentication)
12. [Audit logging](#12-audit-logging)
13. [General security hardening](#13-general-security-hardening)
14. [Routes reference](#14-routes-reference)
15. [Porting checklist](#15-porting-checklist)

---

## 1. Overview & architecture

There are **three independent authentication systems** in this app, each suited to a different
type of actor:

| System | Actor | Credential | Storage | Lifetime |
|---|---|---|---|---|
| Session auth | Staff / Manager / Admin / Head-office users | Username + BCrypt password + mandatory 2FA | `sessions` DB table, signed cookie holding the row id | 12 hours |
| Device JWT | Kiosk tablets (as devices, not users) | `device_id` + BCrypt API key | Stateless JWT (HS256), cached in an encrypted cookie | 24 hours, revocable via `token_version` |
| Display token | Waiting-room TV displays | Inherited from a staff session, then self-sustaining | `ActiveSupport::MessageVerifier`-signed encrypted cookie | 30 days |

All three deliberately use **different cryptographic primitives** (Rails signed cookie /
`Session` DB row, JWT HS256, `MessageVerifier`) so that a compromise of one doesn't
automatically grant tokens usable by another.

A fourth layer, **role-based access control**, sits on top of session auth to gate the
`/admin`, `/manager`, and `/staff` namespaces, plus a public unauthenticated `/:slug` namespace
for booking/check-in.

Every security-relevant event across all of the above is written to a single `AuditLog` table.

---

## 2. Gems required

```ruby
# Gemfile
gem "bcrypt", "~> 3.1.7"   # has_secure_password (users' passwords, devices' API keys)
gem "jwt"                   # kiosk device JWTs
gem "rotp", "~> 6.3"        # TOTP secret generation + code verification
gem "rqrcode", "~> 2.2"     # QR code SVG rendering for TOTP enrollment
gem "rack-attack"           # IP/username request throttling

group :development do
  gem "brakeman", require: false   # static security scanner
end
```

No `devise` or `devise-two-factor` — this whole system is hand-rolled on top of Rails 8's
built-in "has_secure_password + signed-cookie session" generator pattern.

`config/application.rb` needs an explicit require (some Rails autoloading edge case with these
two gems):

```ruby
require "rotp"
require "rqrcode"
```

---

## 3. Database schema

```ruby
create_table "sessions", force: :cascade do |t|
  t.datetime "created_at", null: false
  t.datetime "expires_at", null: false
  t.string   "ip_address"
  t.datetime "last_seen_at"
  t.datetime "updated_at", null: false
  t.string   "user_agent"
  t.bigint   "user_id", null: false
  t.index ["expires_at"]
  t.index ["last_seen_at"]
  t.index ["user_id"]
end

create_table "users", force: :cascade do |t|
  t.datetime "created_at", null: false
  t.string   "email", null: false
  t.integer  "failed_login_attempts", default: 0, null: false
  t.string   "first_name"
  t.string   "last_name"
  t.datetime "last_sign_in_at"
  t.datetime "locked_until"
  t.datetime "password_changed_at"
  t.string   "password_digest", null: false
  t.datetime "password_expires_at"
  t.boolean  "password_reset_required", default: true, null: false
  t.datetime "pii_redacted_at"
  t.string   "role", default: "staff", null: false
  t.datetime "totp_enabled_at"
  t.integer  "totp_last_used_at"   # NOTE: integer, not datetime — stores ROTP's verified Unix ts
  t.string   "totp_secret"
  t.datetime "updated_at", null: false
  t.string   "username", null: false
  t.index ["email"], unique: true
  t.index ["locked_until"]
  t.index ["password_expires_at"]
  t.index ["pii_redacted_at"]
  t.index ["role"]
  t.index ["totp_enabled_at"]
  t.index ["username"], unique: true
end

create_table "admin_two_factor_challenges", force: :cascade do |t|
  t.integer  "attempts", default: 0, null: false
  t.string   "challenge_id", null: false
  t.string   "code_digest"
  t.datetime "created_at", null: false
  t.string   "delivery_method", default: "email", null: false
  t.datetime "expires_at", null: false
  t.string   "ip_address"
  t.boolean  "password_expired", default: false, null: false
  t.string   "redirect_after"
  t.datetime "updated_at", null: false
  t.datetime "used_at"
  t.string   "user_agent"
  t.bigint   "user_id", null: false
  t.index ["challenge_id"], unique: true
  t.index ["delivery_method"]
end
add_foreign_key "admin_two_factor_challenges", "users"

create_table "password_histories", force: :cascade do |t|
  t.datetime "created_at", null: false
  t.string   "password_digest", null: false
  t.datetime "updated_at", null: false
  t.bigint   "user_id", null: false
  t.index ["user_id", "created_at"]
  t.index ["user_id"]
end
add_foreign_key "password_histories", "users"

create_table "password_reset_tokens", force: :cascade do |t|
  t.datetime "created_at", null: false
  t.datetime "expires_at", null: false
  t.string   "password_digest_snapshot", null: false
  t.string   "request_ip"
  t.text     "request_user_agent"
  t.string   "token_digest", null: false
  t.datetime "updated_at", null: false
  t.datetime "used_at"
  t.bigint   "user_id", null: false
  t.index ["token_digest"], unique: true
  t.index ["user_id", "expires_at", "used_at"]
  t.index ["user_id"]
end
add_foreign_key "password_reset_tokens", "users"

create_table "devices", force: :cascade do |t|
  t.string   "api_key_digest", null: false
  t.datetime "created_at", null: false
  t.string   "device_id", null: false
  t.datetime "last_seen_at"
  t.string   "name"
  t.bigint   "organisation_id"
  t.string   "registered_ip"
  t.string   "serial_number"
  t.string   "status", default: "active", null: false
  t.integer  "token_version", default: 0, null: false
  t.datetime "updated_at", null: false
  t.index ["device_id"], unique: true
  t.index ["organisation_id"]
  t.index ["status"]
end
add_foreign_key "devices", "organisations"

create_table "audit_logs", force: :cascade do |t|
  t.datetime "created_at", null: false
  t.string   "event_type", null: false
  t.string   "ip_address"
  t.text     "metadata"        # serialized JSON
  t.integer  "organisation_id"
  t.integer  "resource_id"
  t.string   "resource_type"
  t.datetime "updated_at", null: false
  t.string   "user_agent"
  t.bigint   "user_id"
  t.index ["created_at"]
  t.index ["event_type"]
  t.index ["organisation_id", "event_type"]
  t.index ["organisation_id"]
  t.index ["resource_type", "resource_id"]
end
add_foreign_key "audit_logs", "users"
```

This app is multi-tenant (`organisation_id` on most tables, plus a `roles` join table tying a
`manager`/`staff` user to one organisation, and `head_office_roles` tying a `head_office` user
to several). If porting into a single-tenant project, drop `organisation_id`/`roles` concerns
and simplify `User#organisation`/`manager_for?`/`staff_for?` accordingly — everything else
(sessions, 2FA, password rules, JWT, audit log) is orthogonal to multi-tenancy.

---

## 4. Core session authentication (staff/manager/admin)

### 4.1 `Current` — request-scoped attributes

`app/models/current.rb`

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :user_agent, :ip_address

  def user
    session&.user
  end
end
```

### 4.2 `Session` model

`app/models/session.rb`

```ruby
class Session < ApplicationRecord
  belongs_to :user

  SESSION_DURATION = 12.hours

  before_create do
    self.user_agent = Current.user_agent
    self.ip_address = Current.ip_address
    self.expires_at = SESSION_DURATION.from_now
  end

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }

  def expired?
    expires_at <= Time.current
  end

  def time_remaining
    return 0 if expired?
    ((expires_at - Time.current) / 60).to_i  # minutes
  end

  # Cleanup expired sessions (run via cron/scheduled job)
  def self.cleanup_expired!
    expired.destroy_all
  end
end
```

### 4.3 `Authentication` concern — session resumption, cookie, expiry

`app/controllers/concerns/authentication.rb`

```ruby
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    before_action :check_session_expiry
    before_action :check_password_expiry
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      skip_before_action :check_session_expiry, **options
      skip_before_action :check_password_expiry, **options
    end
  end

  private

  def authenticated?
    resume_session
  end

  def require_authentication
    resume_session || redirect_to_login
  end

  def resume_session
    # SECURITY: Only resume active (non-expired) sessions
    if session_record = Session.active.find_by(id: cookies.signed[:session_id])
      Current.session = session_record
      if session_record.respond_to?(:last_seen_at) &&
          (session_record.last_seen_at.blank? || session_record.last_seen_at < 1.minute.ago)
        session_record.update_column(:last_seen_at, Time.current)
      end
      true
    else
      # Clear expired session cookie
      cookies.delete(:session_id) if cookies.signed[:session_id].present?
      false
    end
  end

  def check_session_expiry
    return unless authenticated?

    if Current.session.expired?
      AuditLog.create!(
        user: current_user,
        event_type: :session_destroyed,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { reason: "expired" }
      )

      terminate_session
      redirect_to login_path, alert: "Your session has expired. Please sign in again."
    end
  end

  def check_password_expiry
    return unless authenticated?
    return if controller_name == "passwords" || controller_name == "sessions"

    if current_user.password_expired?
      redirect_to edit_password_path, alert: "Your password has expired. Please change it to continue."
    end
  end

  def redirect_to_login
    redirect_to login_path, alert: "Please sign in to continue."
  end

  def current_user
    Current.user
  end

  def start_new_session_for(user)
    user.sessions.create!(
      user_agent: request.user_agent,
      ip_address: request.remote_ip,
      expires_at: Session::SESSION_DURATION.from_now
    ).tap do |session|
      Current.session = session

      # SECURITY: Set cookie with proper flags
      cookies.signed[:session_id] = {
        value: session.id,
        expires: Session::SESSION_DURATION.from_now,
        httponly: true,
        same_site: :strict,
        secure: Rails.env.production?  # Only send over HTTPS in production
      }

      AuditLog.create!(
        user: user,
        event_type: :session_created,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { session_id: session.id }
      )
    end
  end

  def terminate_session
    if Current.session
      AuditLog.create!(
        user: current_user,
        event_type: :session_destroyed,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { session_id: Current.session.id, reason: "user_logout" }
      )

      Current.session.destroy
    end

    cookies.delete(:session_id)
  end
end
```

Key design points:
- The cookie is **signed, not encrypted** — it only carries a numeric `session.id`, so tamper-proofing
  is sufficient; the real session state (user, expiry) lives server-side.
- Session lookup uses `.active` scope (`expires_at > now`) so an expired row is invisible to
  `resume_session` even before the explicit `check_session_expiry` runs — two layers of the same check.
- `last_seen_at` is throttled to update at most once per minute via `update_column` (bypasses
  validations/callbacks) to avoid a DB write on every request.
- 12-hour fixed window from creation (not sliding) — enforced both by the cookie's `expires:` and the
  DB row's `expires_at`.

### 4.4 `SessionsController` — login, logout, 2FA orchestration, timing-attack mitigation, lockout

`app/controllers/sessions_controller.rb`

```ruby
class SessionsController < ApplicationController
  allow_unauthenticated_access only: [ :new, :create, :two_factor, :verify_two_factor, :resend_two_factor, :email_two_factor_fallback ]

  TWO_FACTOR_EXPIRY = 10.minutes
  TWO_FACTOR_MAX_ATTEMPTS = 5
  TRUSTED_TWO_FACTOR_DURATION = 24.hours
  TRUSTED_TWO_FACTOR_COOKIE = :trusted_two_factor
  DUMMY_PASSWORD_DIGEST = BCrypt::Password.new(
    "$2a$12$oN87mVUIPSdKiVLXvhCOV./yAb4oP05YIT4iHuYXX7SFZ.Ly/WIYe"
  )

  def new
    redirect_to after_login_path if authenticated?
  end

  def create
    username = normalized_login_username
    user = valid_login_username?(username) ? User.find_by(username: username) : nil

    if user&.locked?
      AuditLog.create!(user: user, event_type: :login_failure, ip_address: request.remote_ip,
        user_agent: request.user_agent, metadata: { username: username, reason: "account_locked" })
      consume_password_timing(params[:password])
      render_invalid_login
      return
    end

    if user&.password_expired?
      if user.authenticate(params[:password])
        if user.organisation_disabled?
          AuditLog.create!(user: user, event_type: :login_failure, ip_address: request.remote_ip,
            user_agent: request.user_agent, metadata: { username: username, reason: user.organisation_disabled_reason })
          render_invalid_login
          return
        end

        if two_factor_required_for?(user) && !trusted_two_factor_device?(user)
          return unless begin_two_factor_for(user, redirect_after: edit_password_path, password_expired: true)

          user.require_password_reset!
          user.reset_failed_login!
          redirect_to two_factor_login_path, alert: "Your password has expired. Complete security verification, then change your password."
        else
          user.require_password_reset!
          user.reset_failed_login!
          user.update(last_sign_in_at: Time.current)
          complete_login_for(user, redirect_after: edit_password_path, password_expired: true, trusted_device: trusted_two_factor_device?(user))
        end
        return
      end
    end

    authenticated = if user
      user.authenticate(params[:password])
    else
      consume_password_timing(params[:password])
      false
    end

    unless authenticated
      sleep(rand(0.1..0.5))
    end

    if authenticated
      if user.organisation_disabled?
        AuditLog.create!(user: user, event_type: :login_failure, ip_address: request.remote_ip,
          user_agent: request.user_agent, metadata: { username: username, reason: user.organisation_disabled_reason })
        render_invalid_login
        return
      end

      if two_factor_required_for?(user) && !trusted_two_factor_device?(user)
        return unless begin_two_factor_for(user, redirect_after: (user.password_reset_required? ? edit_password_path : dashboard_path))

        user.reset_failed_login!
        redirect_to two_factor_login_path, notice: two_factor_started_notice(user)
      else
        user.reset_failed_login!
        complete_login_for(user, trusted_device: true)
      end

    else
      user&.increment_failed_login!

      AuditLog.create!(user: user, event_type: :login_failure, ip_address: request.remote_ip,
        user_agent: request.user_agent, metadata: { username: username, attempts: user&.failed_login_attempts || 0 })

      render_invalid_login
    end
  end

  def two_factor
    challenge = two_factor_challenge
    redirect_to login_path, alert: "Please sign in to continue." and return unless pending_two_factor_user(challenge)

    assign_two_factor_view_state(challenge)
  end

  def verify_two_factor
    challenge = two_factor_challenge
    user = challenge&.user
    unless user && challenge
      redirect_to login_path, alert: "Your security code has expired. Please sign in again."
      return
    end

    if two_factor_expired?(challenge)
      clear_two_factor_challenge
      redirect_to login_path, alert: "Your security code has expired. Please sign in again."
      return
    end

    if valid_two_factor_code?(params[:code], challenge)
      redirect_after = challenge.redirect_after.presence || dashboard_path
      password_expired = challenge.password_expired?

      challenge.update!(used_at: Time.current)
      trust_two_factor_device_for(user) if params[:remember_device] == "1"
      clear_two_factor_challenge(delete_record: false)
      complete_login_for(user, redirect_after: redirect_after, password_expired: password_expired)
    else
      challenge.increment!(:attempts)

      AuditLog.create!(user: user, event_type: :two_factor_failure, ip_address: request.remote_ip,
        user_agent: request.user_agent, metadata: { attempts: challenge[:attempts] })

      if challenge[:attempts] >= TWO_FACTOR_MAX_ATTEMPTS
        clear_two_factor_challenge
        redirect_to login_path, alert: "Too many incorrect security codes. Please sign in again."
      else
        assign_two_factor_view_state(challenge)
        flash.now[:alert] = "Invalid security code. Please try again."
        render :two_factor, status: :unprocessable_entity
      end
    end
  end

  def resend_two_factor
    challenge = two_factor_challenge
    user = challenge&.user
    unless user && challenge
      redirect_to login_path, alert: "Please sign in to continue."
      return
    end

    if challenge.delivery_method_totp?
      redirect_to two_factor_login_path, alert: "Use your authenticator app, or request an email code."
      return
    end

    begin_two_factor_for(user, redirect_after: challenge.redirect_after.presence || dashboard_path,
      password_expired: challenge.password_expired?)
    redirect_to two_factor_login_path
  end

  def email_two_factor_fallback
    challenge = two_factor_challenge
    user = challenge&.user
    unless user && challenge&.delivery_method_totp?
      redirect_to login_path, alert: "Please sign in to continue."
      return
    end

    AuditLog.create!(user: user, event_type: :totp_email_fallback_requested,
      ip_address: request.remote_ip, user_agent: request.user_agent)

    begin_two_factor_for(user, redirect_after: challenge.redirect_after.presence || dashboard_path,
      password_expired: challenge.password_expired?, delivery_method: "email")
    redirect_to two_factor_login_path
  end

  def destroy
    session_record = Current.session

    AuditLog.create!(user: current_user, event_type: :logout, ip_address: request.remote_ip,
      user_agent: request.user_agent, metadata: { session_id: session_record&.id })

    terminate_session
    redirect_to root_path, notice: "Signed out successfully."
  end

  private

  def normalized_login_username
    params[:username].to_s.strip.downcase
  end

  def valid_login_username?(username)
    username.match?(User::USERNAME_FORMAT)
  end

  def after_login_path
    dashboard_path
  end

  # Hook point — currently unconditional, but kept as a method so a future
  # per-role/per-org 2FA policy can be added without touching call sites.
  def two_factor_required_for?(user)
    true
  end

  def begin_two_factor_for(user, redirect_after:, password_expired: false, delivery_method: nil)
    delivery_method ||= user.totp_enabled? ? "totp" : "email"

    if delivery_method == "email" && !user.email.present?
      AuditLog.create!(user: user, event_type: :login_failure, ip_address: request.remote_ip,
        user_agent: request.user_agent, metadata: { username: user.username, reason: "admin_email_missing" })
      flash.now[:alert] = "This account requires an email address for security verification. Please contact an administrator."
      render :new, status: :unprocessable_entity
      return false
    end

    code = delivery_method == "email" ? format("%06d", SecureRandom.random_number(1_000_000)) : nil
    challenge_id = SecureRandom.urlsafe_base64(24)
    clear_two_factor_challenge
    reset_session   # regenerate session id — defends against session fixation
    session[:two_factor_challenge_id] = challenge_id
    AdminTwoFactorChallenge.create!(
      user: user,
      challenge_id: challenge_id,
      code_digest: (two_factor_digest(code) if code),
      expires_at: TWO_FACTOR_EXPIRY.from_now,
      attempts: 0,
      delivery_method: delivery_method,
      redirect_after: redirect_after,
      password_expired: password_expired,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if delivery_method == "email"
      TwoFactorMailer.login_code(user, code, expires_in_minutes: (TWO_FACTOR_EXPIRY / 1.minute).to_i,
        request_details: two_factor_request_details).deliver_later
    end

    AuditLog.create!(user: user, event_type: :two_factor_challenge_sent, ip_address: request.remote_ip,
      user_agent: request.user_agent, metadata: { delivery_method: delivery_method })

    true
  end

  def complete_login_for(user, redirect_after: nil, password_expired: false, trusted_device: false)
    user.update(last_sign_in_at: Time.current)
    start_new_session_for(user)

    unless trusted_device
      AuditLog.create!(user: user, event_type: :two_factor_success, ip_address: request.remote_ip,
        user_agent: request.user_agent)
    end

    AuditLog.create!(user: user, event_type: :login_success, ip_address: request.remote_ip,
      user_agent: request.user_agent, metadata: { password_expired: password_expired, trusted_device: trusted_device }.compact)

    if redirect_after.present?
      if redirect_after == edit_password_path
        redirect_to redirect_after, notice: "Please change your temporary password."
      else
        redirect_to redirect_after
      end
    elsif user.password_reset_required?
      redirect_to edit_password_path, notice: "Please change your temporary password."
    else
      redirect_to dashboard_path
    end
  end

  def pending_two_factor_user(challenge = two_factor_challenge)
    challenge&.user
  end

  def two_factor_expired?(challenge)
    challenge.expired?
  end

  def valid_two_factor_code?(code, challenge)
    return challenge.user.verify_totp!(code) if challenge.delivery_method_totp?

    submitted = code.to_s.gsub(/\D/, "")
    return false unless submitted.length == 6

    ActiveSupport::SecurityUtils.secure_compare(two_factor_digest(submitted), challenge.code_digest.to_s)
  end

  def assign_two_factor_view_state(challenge)
    @two_factor_delivery_method = challenge.delivery_method
    @two_factor_email = challenge.user.email
  end

  def two_factor_started_notice(user)
    user.totp_enabled? ? "Enter the code from your authenticator app." : "Enter the security code sent to your email."
  end

  def two_factor_digest(code)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, code.to_s)
  end

  def trusted_two_factor_device?(user)
    payload = cookies.encrypted[TRUSTED_TWO_FACTOR_COOKIE]
    data = JSON.parse(payload.to_s)
    return false unless data["user_id"].to_i == user.id
    return false unless data["expires_at"].present? && Time.iso8601(data["expires_at"]).future?

    ActiveSupport::SecurityUtils.secure_compare(data["verifier"].to_s, trusted_two_factor_verifier(user))
  rescue ArgumentError, JSON::ParserError, TypeError
    false
  end

  def trust_two_factor_device_for(user)
    expires_at = TRUSTED_TWO_FACTOR_DURATION.from_now
    cookies.encrypted[TRUSTED_TWO_FACTOR_COOKIE] = {
      value: { user_id: user.id, verifier: trusted_two_factor_verifier(user), expires_at: expires_at.iso8601 }.to_json,
      expires: expires_at,
      httponly: true,
      same_site: :strict,
      secure: Rails.env.production?
    }
  end

  # Binding the verifier to password_digest means changing the password
  # auto-invalidates every trusted-device cookie for that user.
  def trusted_two_factor_verifier(user)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base,
      [ user.id, user.password_digest, request.user_agent.to_s ].join(":"))
  end

  def clear_two_factor_challenge(delete_record: true)
    if delete_record && session[:two_factor_challenge_id].present?
      AdminTwoFactorChallenge.where(challenge_id: session[:two_factor_challenge_id]).delete_all
    end
    session.delete(:two_factor_challenge_id)
    clear_legacy_two_factor_session_keys
  end

  def two_factor_challenge
    challenge_id = session[:two_factor_challenge_id]
    return nil if challenge_id.blank?

    AdminTwoFactorChallenge.active.find_by(challenge_id: challenge_id)
  end

  def two_factor_request_details
    { ip_address: request.remote_ip, user_agent: request.user_agent, requested_at: Time.current.iso8601 }
  end

  def clear_legacy_two_factor_session_keys
    session.delete(:two_factor_user_id)
    session.delete(:two_factor_code_digest)
    session.delete(:two_factor_expires_at)
    session.delete(:two_factor_attempts)
    session.delete(:two_factor_redirect_after)
    session.delete(:two_factor_password_expired)
  end

  # Always pays the bcrypt cost, even when the username doesn't resolve to a
  # real user, so response timing can't be used to enumerate usernames.
  def consume_password_timing(password)
    DUMMY_PASSWORD_DIGEST.is_password?(password.to_s)
  end

  def render_invalid_login
    flash.now[:alert] = "Invalid credentials. Please try again."
    render :new, status: :unprocessable_entity
  end
end
```

### 4.5 Account lockout — `User` model excerpt

```ruby
MAX_LOGIN_ATTEMPTS = 5
LOCKOUT_DURATION = 30.minutes

def locked?
  locked_until.present? && locked_until > Time.current
end

# Distinguishes a manual admin-triggered disable from a temporary lockout.
def disabled?
  locked_until.present? && locked_until > 50.years.from_now
end

def disable!
  update!(locked_until: 100.years.from_now, failed_login_attempts: 0)
  sessions.destroy_all
  AuditLog.create!(user: self, event_type: :account_locked, ip_address: Current.ip_address,
    user_agent: Current.user_agent, metadata: { reason: "manually_disabled" })
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
```

This is a **second, independent** brute-force layer from Rack::Attack (§13.3) — Rack::Attack
throttles by IP/username at the HTTP layer and resets after its time window regardless of
outcome; this lockout is persistent per-account and only resets on a *successful* login.

---

## 5. Two-factor authentication (TOTP + email fallback)

**2FA is mandatory for every login**, for every role — `two_factor_required_for?` in
`SessionsController` (§4.4) is a hardcoded `true`. What's actually optional is *which* second
factor: if the user has enrolled an authenticator app (`user.totp_enabled?`), TOTP is used;
otherwise the system automatically falls back to a one-time 6-digit **email** code. There is no
path that skips the second factor. An admin/staff account with no email and no TOTP enrolled
literally cannot log in — this is treated as a deliberate hard-fail, not a bug.

### 5.1 `User` model — TOTP secret, verification, replay protection

```ruby
TOTP_ISSUER = "RxTerminal"

encrypts :totp_secret   # Active Record Encryption, non-deterministic

def totp_enabled?
  totp_secret.present? && totp_enabled_at.present?
end

def self.generate_totp_secret
  ROTP::Base32.random_base32
end

def totp_provisioning_uri(secret = totp_secret)
  ROTP::TOTP.new(secret, issuer: TOTP_ISSUER).provisioning_uri(username)
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
```

- **Replay protection**: `verify_totp!` passes `after: totp_last_used_at` into ROTP's `verify`,
  then persists the timestamp ROTP returns — this stops the *same* 30-second code being accepted
  twice, even from a different request/IP.
- **Drift window**: `drift_behind: 30, drift_ahead: 30` (seconds) tolerates ~1 time-step of clock skew.
- `totp_last_used_at` is an **integer** column (Unix timestamp from ROTP), not a `datetime` —
  intentional, matches what `ROTP::TOTP#verify` returns.

### 5.2 `AdminTwoFactorChallenge` model — persisted login-time challenge

`app/models/admin_two_factor_challenge.rb`

```ruby
class AdminTwoFactorChallenge < ApplicationRecord
  belongs_to :user

  enum :delivery_method, { email: "email", totp: "totp" }, prefix: true

  scope :active, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def expired?
    expires_at <= Time.current
  end

  def active?
    used_at.blank? && !expired?
  end
end
```

Despite the "Admin" in the class name (legacy from when only admins had 2FA), this is used for
**every** role. The session only stores the opaque `challenge_id` (`session[:two_factor_challenge_id]`)
— the code digest, delivery method, attempt counter, and expiry all live server-side in this row,
so a stolen session cookie mid-challenge reveals nothing usable and the challenge survives a
server restart. Email codes are HMAC-SHA256-digested before storage (raw code never persisted);
comparison uses `ActiveSupport::SecurityUtils.secure_compare` (constant-time). Max 5 attempts
(`TWO_FACTOR_MAX_ATTEMPTS`), 10-minute expiry (`TWO_FACTOR_EXPIRY`) — see full flow in §4.4.

### 5.3 TOTP enrollment/disable — `ProfileController`

`app/controllers/profile_controller.rb`

```ruby
class ProfileController < ApplicationController
  before_action :require_authentication

  def show; end
  def edit; end

  def update
    if current_user.update(profile_params)
      redirect_to profile_path, notice: "Profile updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def new_totp
    if current_user.totp_enabled?
      redirect_to profile_path, notice: "Authenticator app verification is already enabled."
      return
    end

    # Stash the secret in session so revisiting the page doesn't regenerate
    # a new secret/QR code each time (which would desync an already-scanned app).
    session[:pending_totp_secret] ||= User.generate_totp_secret
    @totp_secret = session[:pending_totp_secret]
    @totp_qr_svg = RQRCode::QRCode.new(current_user.totp_provisioning_uri(@totp_secret)).as_svg(
      module_size: 4, standalone: true, use_path: true
    )
  end

  def create_totp
    @totp_secret = session[:pending_totp_secret]

    unless @totp_secret.present?
      redirect_to new_profile_totp_path, alert: "Start authenticator app setup again."
      return
    end

    unless current_user.authenticate(params[:current_password])
      rebuild_totp_qr
      flash.now[:alert] = "Current password is incorrect."
      render :new_totp, status: :unprocessable_entity
      return
    end

    unless current_user.valid_totp_code?(params[:code], @totp_secret)
      rebuild_totp_qr
      flash.now[:alert] = "Authenticator code is invalid. Please try again."
      render :new_totp, status: :unprocessable_entity
      return
    end

    current_user.enable_totp!(@totp_secret)
    session.delete(:pending_totp_secret)

    AuditLog.create!(user: current_user, event_type: :totp_enabled, ip_address: request.remote_ip, user_agent: request.user_agent)

    redirect_to profile_path, notice: "Authenticator app verification has been enabled."
  end

  def destroy_totp
    unless current_user.totp_enabled?
      redirect_to profile_path, notice: "Authenticator app verification is not enabled."
      return
    end

    unless current_user.authenticate(params[:current_password])
      redirect_to profile_path, alert: "Current password is incorrect."
      return
    end

    current_session_id = Current.session&.id
    current_user.disable_totp!
    # Force re-verification everywhere except the browser that just proved the password.
    current_user.sessions.where.not(id: current_session_id).destroy_all

    AuditLog.create!(user: current_user, event_type: :totp_disabled, ip_address: request.remote_ip,
      user_agent: request.user_agent, metadata: { other_sessions_destroyed: true })

    redirect_to profile_path, notice: "Authenticator app verification has been disabled."
  end

  private

  def profile_params
    params.require(:user).permit(:first_name, :last_name, :email)
  end

  def rebuild_totp_qr
    @totp_qr_svg = RQRCode::QRCode.new(current_user.totp_provisioning_uri(@totp_secret)).as_svg(
      module_size: 4, standalone: true, use_path: true
    )
  end
end
```

Both enrollment and disable require re-entering the **current password** — 2FA state changes
are treated as sensitive as a password change.

### 5.4 Views (structure to replicate)

- `app/views/profile/new_totp.html.erb` — renders the QR SVG via `sanitize(@totp_qr_svg, tags: %w[svg path rect g], attributes: %w[xmlns viewBox width height d fill id class version shape-rendering transform])` (RQRCode's raw SVG is untrusted-shaped output, so it's sanitized before inlining), plus the raw base32 secret as a manual-entry fallback, plus a form for current password + 6-digit code.
- `app/views/profile/show.html.erb` — "Security" card: password expiry countdown, TOTP status + Set Up/Disable button (disable is a small inline form re-asking for the password), Sign out button.
- `app/views/sessions/two_factor.html.erb` — single 6-digit code input (`inputmode: "numeric"`, `autocomplete: "one-time-code"`, `pattern: "[0-9]{6}"`), a "Trust this device for 24 hours" checkbox, and a context-sensitive secondary link (TOTP users see "Email me a code instead"; email-code users see "Send a new code").

### 5.5 Email-code delivery — `TwoFactorMailer`

`app/mailers/two_factor_mailer.rb`

```ruby
class TwoFactorMailer < ApplicationMailer
  def login_code(user, code, expires_in_minutes:, request_details: {})
    @user = user
    @code = code
    @expires_in_minutes = expires_in_minutes
    @request_details = request_details || {}
    @requested_at = parse_requested_at(@request_details[:requested_at])

    attachments.inline["rxterminal-title.png"] = File.binread(Rails.root.join("app/assets/images/RxTerminal-Title.png"))

    mail(to: user.email, subject: "Your RxTerminal security code")
  end

  private

  def parse_requested_at(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    Time.current
  end
end
```

The email body should show the request's IP/user-agent/time so a recipient can spot a login
attempt that isn't theirs.

### 5.6 Trusted device / "remember this device for 24 hours"

Already shown in full in §4.4 (`trusted_two_factor_device?`, `trust_two_factor_device_for`,
`trusted_two_factor_verifier`). The key trick: the verifier HMAC is keyed on
`[user.id, user.password_digest, user_agent]`, so **changing the password automatically
invalidates every trusted-device cookie** with zero extra bookkeeping.

### 5.7 Known gap — no static backup/recovery codes

There are no pre-generated backup codes for a lost authenticator device. Recovery relies on
`email_two_factor_fallback` (a live, single-use, HMAC-digested code to the user's registered
email). If porting to a project where users might not have a reliable email address available
at 2FA time, consider adding static one-time backup codes as well.

---

## 6. Password strength & lifecycle

All in the `User` model — no separate `app/validators/` class, no `zxcvbn`-style entropy
scoring, purely regex/pattern-based.

```ruby
MIN_PASSWORD_LENGTH = 8
PASSWORD_HISTORY_LIMIT = 10
PASSWORD_EXPIRY_DAYS = 90

validates :password,
    length: { minimum: MIN_PASSWORD_LENGTH, message: "must be at least #{MIN_PASSWORD_LENGTH} characters" },
    format: {
      with: /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d).*\z/,
      message: "must include at least one lowercase letter, one uppercase letter, and one digit"
    },
    if: :password_digest_changed?

# PASSWORD VALIDATION CHECK -- REMOVE THESE IF TOO RESTRICTIVE
validate :password_not_common, if: :password_digest_changed?
validate :password_no_sequential_patterns, if: :password_digest_changed?
validate :password_no_repeated_characters, if: :password_digest_changed?
validate :password_no_keyboard_patterns, if: :password_digest_changed?
validate :password_not_in_history, if: :password_digest_changed?

before_save :set_password_timestamps, if: :password_digest_changed?
after_update :save_password_to_history, if: :saved_change_to_password_digest?

def password_expired?
  return false if password_expires_at.nil?
  password_expires_at < Time.current
end

def days_until_password_expires
  return nil if password_expires_at.nil?
  ((password_expires_at - Time.current) / 1.day).to_i
end

def require_password_reset!
  update!(password_reset_required: true)
end

private

# --- Password Security Pattern Detection ---

def password_not_common
  return unless password.present?

  common_passwords = %w[
    password password123 12345678 qwerty123 admin123
    welcome1 letmein1 Password1 Qwerty123 Admin123
    organisation organisation123 Organisation1 Healthcare1
    pass123 passw0rd Passw0rd Welcome123
  ]

  if common_passwords.any? { |cp| password.downcase == cp.downcase }
    errors.add(:password, "is too common. Please choose a more unique password.")
    return
  end

  common_words = %w[password pass admin welcome letmein organisation healthcare]
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

# --- Password Lifecycle Callbacks ---

def set_password_timestamps
  self.password_changed_at = Time.current
  self.password_expires_at = PASSWORD_EXPIRY_DAYS.days.from_now
end

def save_password_to_history
  old_digest = password_digest_before_last_save || password_digest
  password_histories.create!(password_digest: old_digest)

  old_passwords = password_histories.order(created_at: :desc).offset(PASSWORD_HISTORY_LIMIT)
  PasswordHistory.where(id: old_passwords.pluck(:id)).destroy_all
end
```

Rules summary: **min 8 chars, 1 upper + 1 lower + 1 digit** (no symbol requirement), rejects an
explicit common-password list and substrings of common words, rejects sequential/reverse-sequential
number and letter runs, rejects 3+ repeated identical characters, rejects keyboard-walk substrings,
and rejects reuse of any of the last **10** passwords. Password **expires after 90 days**
(`password_expires_at` stamped in a `before_save` whenever the digest changes).

### 6.1 `PasswordHistory` model

`app/models/password_history.rb`

```ruby
class PasswordHistory < ApplicationRecord
  belongs_to :user

  validates :password_digest, presence: true

  def self.password_used_before?(user, password)
    user.password_histories
      .order(created_at: :desc)
      .limit(10)
      .any? { |ph| BCrypt::Password.new(ph.password_digest) == password }
  end
end
```

### 6.2 Changing your own password — `PasswordsController`

`app/controllers/passwords_controller.rb`

```ruby
class PasswordsController < ApplicationController
  def edit
    if current_user.password_expires_at.present?
      @days_until_expiry = current_user.days_until_password_expires

      if @days_until_expiry.present? && @days_until_expiry <= 14 && @days_until_expiry > 0
        flash.now[:warning] = "Your password will expire in #{@days_until_expiry} days."
      end
    end
  end

  def update
    user = current_user

    unless user.authenticate(params[:current_password])
      AuditLog.create!(user: user, event_type: :password_change, ip_address: request.remote_ip,
        user_agent: request.user_agent, metadata: { success: false, reason: "incorrect_current_password" })

      flash.now[:alert] = "Current password is incorrect"
      render :edit, status: :unprocessable_entity
      return
    end

    if user.update(password: params[:password], password_confirmation: params[:password_confirmation])
      user.update!(password_reset_required: false)

      user.notifications.where(notification_type: [ :password_expiring, :password_expired ]).pending.find_each(&:dismiss!)

      # Invalidate all other sessions - keep only the current one
      user.sessions.where.not(id: Current.session.id).destroy_all

      AuditLog.create!(user: user, event_type: :password_change, ip_address: request.remote_ip,
        user_agent: request.user_agent, metadata: { success: true })

      redirect_to after_password_change_path, notice: "Password updated successfully!"
    else
      AuditLog.create!(user: user, event_type: :password_change, ip_address: request.remote_ip,
        user_agent: request.user_agent, metadata: { success: false, reason: "validation_failed", errors: user.errors.full_messages })

      flash.now[:alert] = user.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def after_password_change_path
    case current_user.role
    when "admin" then admin_root_path
    when "manager" then manager_root_path
    when "staff" then staff_root_path
    else root_path
    end
  end
end
```

### 6.3 Forced password reset / temporary-password enforcement

`app/controllers/concerns/password_reset_enforcement.rb`

```ruby
module PasswordResetEnforcement
  extend ActiveSupport::Concern

  included do
    before_action :enforce_password_reset
  end

  private

  def enforce_password_reset
    return unless authenticated?
    return unless current_user.password_reset_required?

    return if controller_name == "passwords" && action_name.in?(%w[edit update])
    return if controller_name == "sessions" && action_name == "destroy"

    redirect_to edit_password_path, alert: "You must change your password before continuing."
  end
end
```

Included in `ApplicationController` alongside `Authentication` (§13.1) — locks a user with a
temporary/admin-reset password down to only the password-change page and logout, everywhere
else in the app.

### 6.4 Expiry warning notifications — `PasswordExpiryNotificationJob`

`app/jobs/password_expiry_notification_job.rb`

```ruby
class PasswordExpiryNotificationJob < ApplicationJob
  queue_as :default

  def perform
    warning_days = [ 14, 7, 3, 1 ]
    notifications_created = 0

    warning_days.each do |days|
      expiring_date = days.days.from_now.to_date

      User.where(password_expires_at: expiring_date.beginning_of_day..expiring_date.end_of_day).find_each do |user|
        next if user.notifications.active
          .where(notification_type: :password_expiring)
          .where("metadata LIKE ?", "%days_remaining: #{days}%")
          .exists?

        result = Notifications::Sender.new(
          title: "Password Expiring Soon",
          message: "Your password will expire in #{days} #{'day'.pluralize(days)}. Please change it to continue accessing the system.",
          notification_type: :password_expiring,
          recipients: [ user ],
          metadata: { days_remaining: days, expires_at: user.password_expires_at.iso8601 }
        ).call

        notifications_created += result.notifications_created
      end
    end

    Rails.logger.info "Password expiry check complete: #{notifications_created} notifications created"
  end
end
```

Run this on a recurring schedule (e.g. daily via Solid Queue recurring tasks / `cron`). Porting
without the in-app `Notifications::Sender` system: swap the notification call for an email or
whatever your target project's notification mechanism is — the querying/dedup logic (exact-day
match on `password_expires_at`, dedup on `days_remaining` in metadata) is the reusable part.

---

## 7. Password reset ("forgot password")

### 7.1 `PasswordResetToken` model

`app/models/password_reset_token.rb`

```ruby
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
  # (e.g. by an admin) between the reset request and its use.
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
```

Only an HMAC digest of the raw token is ever persisted — the raw token exists only in memory
and in the outbound email.

### 7.2 `PasswordResetsController`

`app/controllers/password_resets_controller.rb`

```ruby
class PasswordResetsController < ApplicationController
  allow_unauthenticated_access only: [ :new, :create, :edit, :update ]

  GENERIC_NOTICE = "If that account exists, a password reset link has been sent."
  INVALID_TOKEN_ALERT = "This password reset link is invalid or has expired."
  RESET_REQUEST_WINDOW = 10.minutes
  RESET_REQUESTS_PER_IP = 5
  RESET_REQUESTS_PER_USERNAME = 3

  def new; end

  def create
    username = normalized_username
    user = valid_username?(username) ? User.find_by(username: username) : nil

    log_reset_requested(user, username)

    if reset_request_throttled?(username)
      log_rate_limit(user, username)
      redirect_to new_password_reset_path, notice: GENERIC_NOTICE
      return
    end

    if resettable_user?(user)
      _record, raw_token = PasswordResetToken.generate_for!(user, request_ip: request.remote_ip, request_user_agent: request.user_agent)

      PasswordResetMailer.reset_link(user, raw_token, request_details: reset_request_details).deliver_later

      AuditLog.create!(user: user, event_type: :password_reset_link_sent, ip_address: request.remote_ip,
        user_agent: request.user_agent, metadata: { username: user.username })
    else
      consume_reset_timing
    end

    # Always the same redirect/notice regardless of whether the account exists —
    # prevents user enumeration via response content or timing.
    redirect_to new_password_reset_path, notice: GENERIC_NOTICE
  end

  def edit
    @token = params[:token].to_s
    @password_reset_token = usable_token_for(@token)

    redirect_to new_password_reset_path, alert: INVALID_TOKEN_ALERT unless @password_reset_token
  end

  def update
    @token = params[:token].to_s
    @password_reset_token = usable_token_for(@token)

    unless @password_reset_token
      redirect_to new_password_reset_path, alert: INVALID_TOKEN_ALERT
      return
    end

    user = @password_reset_token.user

    ActiveRecord::Base.transaction do
      unless user.update(password: params[:password], password_confirmation: params[:password_confirmation])
        raise ActiveRecord::Rollback
      end

      user.update!(password_reset_required: false, failed_login_attempts: 0, locked_until: nil)
      user.sessions.destroy_all
      @password_reset_token.consume!
    end

    if user.errors.empty?
      AuditLog.create!(user: user, event_type: :password_reset_completed, ip_address: request.remote_ip,
        user_agent: request.user_agent, metadata: { username: user.username })

      redirect_to login_path, notice: "Your password has been reset. Sign in with your new password."
    else
      AuditLog.create!(user: user, event_type: :password_reset_failed, ip_address: request.remote_ip,
        user_agent: request.user_agent, metadata: { username: user.username, reason: "validation_failed", errors: user.errors.full_messages })

      flash.now[:alert] = user.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def normalized_username
    params[:username].to_s.strip.downcase
  end

  def valid_username?(username)
    username.present? && username.match?(User::USERNAME_FORMAT)
  end

  def resettable_user?(user)
    user.present? && user.email.present? && user.pii_redacted_at.blank? && !user.disabled? && !user.organisation_disabled?
  end

  def usable_token_for(raw_token)
    token = PasswordResetToken.find_usable(raw_token)
    return nil unless token&.usable?
    return nil unless resettable_user?(token.user)

    token
  end

  def reset_request_throttled?(username)
    ip_throttled = increment_throttle("password_reset:ip:#{request.remote_ip.presence || 'unknown'}") > RESET_REQUESTS_PER_IP
    username_throttled = valid_username?(username) && increment_throttle("password_reset:username:#{username}") > RESET_REQUESTS_PER_USERNAME
    ip_throttled || username_throttled
  end

  def increment_throttle(key)
    count = Rails.cache.increment(key, 1, expires_in: RESET_REQUEST_WINDOW)
    return count if count

    Rails.cache.write(key, 1, expires_in: RESET_REQUEST_WINDOW)
    1
  end

  def log_reset_requested(user, username)
    AuditLog.create!(user: user, event_type: :password_reset_requested, ip_address: request.remote_ip,
      user_agent: request.user_agent, metadata: { username: username.presence })
  end

  def log_rate_limit(user, username)
    AuditLog.create!(user: user, event_type: :rate_limit_triggered, ip_address: request.remote_ip,
      user_agent: request.user_agent, metadata: { scope: "password_reset", username: username.presence })
  end

  def reset_request_details
    { ip_address: request.remote_ip, user_agent: request.user_agent, requested_at: Time.current.iso8601 }
  end

  # Keeps response timing constant for non-existent/non-resettable accounts.
  def consume_reset_timing
    PasswordResetToken.digest(SecureRandom.urlsafe_base64(PasswordResetToken::TOKEN_BYTES))
  end
end
```

Layered defenses: a **generic response** regardless of account existence, a **cache-based
double throttle** (by IP and by username, 10-minute window, `Rails.cache.increment`), a
**timing-safe no-op** for non-resettable accounts, single-use tokens consumed in a transaction,
and destroying **all** sessions + clearing lockout state on successful reset.

### 7.3 `PasswordResetMailer`

`app/mailers/password_reset_mailer.rb`

```ruby
class PasswordResetMailer < ApplicationMailer
  def reset_link(user, token, request_details: {})
    @user = user
    @token = token
    @reset_url = edit_password_reset_url(token)
    @expires_in_minutes = (PasswordResetToken::EXPIRY / 1.minute).to_i
    @request_details = request_details || {}
    @requested_at = parse_requested_at(@request_details[:requested_at])

    attachments.inline["rxterminal-title.png"] = File.binread(Rails.root.join("app/assets/images/RxTerminal-Title.png"))

    mail(to: user.email, subject: "Reset your RxTerminal password")
  end

  private

  def parse_requested_at(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    Time.current
  end
end
```

---

## 8. The `/profile` route

`resource :profile, only: [ :show, :edit, :update ], controller: "profile"` — a **singular**
resource, always operating on `current_user` (no id in the URL). Full controller is in §5.3;
`show`/`edit`/`update` only touch `first_name`, `last_name`, `email` — username, role, and
password are deliberately **not** editable from this form (password changes go through the
separate `resource :password` / `PasswordsController`, §6.2).

What's on the page (`app/views/profile/show.html.erb`):
- **Personal Details card**: first/last name, username (read-only), email, role badge, last
  sign-in (`time_ago_in_words`).
- **Security card**: password expiry countdown (amber warning at ≤14 days, red "Expired" at
  ≤0 — reusing `current_user.days_until_password_expires`), TOTP status + Set Up/Disable,
  Sign out button.

What's deliberately **not** in `/profile`: no session/device list, no self-service audit-log
view, no self-service account deletion (that's admin/job-driven only via a PII-redaction
service). If the target project wants those, they're natural additions on top of this
structure — `current_user.sessions` and `current_user.audit_logs` are already available
relations, just not surfaced in a view yet.

---

## 9. Role-based access control (RBAC) & multi-tenant org selection

`app/controllers/concerns/role_authentication.rb`

```ruby
module RoleAuthentication
    extend ActiveSupport::Concern

    included do
        before_action :authenticate_user!
        before_action :check_role_access
        before_action :ensure_admin_organisation_selected
    end

    private

    def authenticate_user!
        @current_user = find_current_user
        redirect_to root_path unless @current_user
    end

    def find_current_user
        current_user   # delegates to Authentication concern
    end

    def check_role_access
        controller_namespace = params[:controller].split("/").first
        organisation = current_organisation

        case controller_namespace
        when "admin"
            redirect_to root_path unless @current_user&.admin?
        when "manager"
            redirect_to root_path unless @current_user&.manager_for?(organisation)
            check_head_office_organisation!(organisation) if @current_user&.head_office?
            check_organisation_active!(organisation)
        when "staff"
            redirect_to root_path unless @current_user&.staff_for?(organisation)
            check_head_office_organisation!(organisation) if @current_user&.head_office?
            check_organisation_active!(organisation)
        else
            redirect_to root_path unless @kiosk&.authenticated?
        end
    end

    def check_organisation_active!(organisation)
        return if organisation.nil?
        return if organisation.active?
        return if @current_user&.admin? && organisation.archived?

        terminate_session
        redirect_to login_path, alert: "Your organisation account has been disabled. Please contact support."
    end

    def current_organisation
        @current_organisation ||= find_user_organisation
    end

    def find_user_organisation
        if @current_user&.admin? || @current_user&.head_office?
            return Organisation.find_by(id: session[:admin_organisation_id]) if session[:admin_organisation_id].present?
            return nil
        end
        @current_user&.organisation
    end

    def ensure_admin_organisation_selected
        return unless @current_user&.admin? || @current_user&.head_office?
        namespace = params[:controller].split("/").first
        return unless %w[staff manager].include?(namespace)
        return if session[:admin_organisation_id].present?

        redirect_to organisation_picker_path(portal: namespace)
    end

    def check_head_office_organisation!(organisation)
        return unless organisation.present?
        unless @current_user.head_office_covers_organisation?(organisation)
            session.delete(:admin_organisation_id)
            redirect_to organisation_picker_path(portal: params[:controller].split("/").first)
        end
    end
end
```

Namespace is derived from the controller path (`params[:controller].split("/").first`), so
`Admin::UsersController` → `"admin"`, `Manager::ServicesController` → `"manager"`, etc. Admin
and head-office users don't have one fixed organisation — they pick one via
`session[:admin_organisation_id]` (the "organisation picker"), which is how an admin
impersonates/enters a specific tenant's manager or staff portal. `check_organisation_active!`
terminates the session outright if the selected org has been disabled mid-session.

Note: the `else` branch (`@kiosk&.authenticated?`) is a no-op guard left over from before kiosk
auth was split into its own `KioskAuthentication` concern (§10) — `@kiosk` is never actually set
anywhere. Worth cleaning up rather than porting verbatim.

### 9.1 Base controllers wiring, per namespace

```ruby
# app/controllers/admin/base_controller.rb
class Admin::BaseController < ApplicationController
  include RoleAuthentication
  include AuditLogging
end

# app/controllers/manager/base_controller.rb
class Manager::BaseController < ApplicationController
  include RoleAuthentication
  include AuditLogging

  before_action :set_organisation

  private

  def set_organisation
    @organisation = current_organisation
  end
end

# app/controllers/staff/base_controller.rb
class Staff::BaseController < ApplicationController
  include RoleAuthentication
  include AuditLogging
end
```

The public-facing booking/check-in namespace has its own `Public::BaseController` that does
**not** include `RoleAuthentication` at all — it's unauthenticated, and resolves its
organisation from a URL slug instead of session state.

---

## 10. Kiosk device authentication (JWT)

Kiosks authenticate as **devices**, not users — no `User`/session involved at all.

### 10.1 `Device` model

`app/models/device.rb`

```ruby
class Device < ApplicationRecord
  belongs_to :organisation
  has_secure_password :api_key

  validates :device_id, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: %w[active inactive revoked] }
  validates :organisation_id, presence: true

  def touch_last_seen
    update(last_seen_at: Time.current)
  end

  def active?
    status == "active"
  end
end
```

### 10.2 `JwtService`

`app/services/jwt_service.rb`

```ruby
class JwtService
    TOKEN_EXPIRATION = 24.hours.to_i

    def self.secret_key
      key = Rails.application.credentials.jwt_secret_key
      raise "jwt_secret_key is not configured in Rails credentials" if key.blank?
      key
    end

    def self.encode(device_id:, additional_claims: {})
      payload = {
        device_id: device_id,
        type: "device",
        exp: Time.now.to_i + TOKEN_EXPIRATION,
        iat: Time.now.to_i
      }.merge(additional_claims)

      JWT.encode(payload, secret_key, "HS256")
    end

    def self.decode(token)
      decoded = JWT.decode(token, secret_key, true, { algorithm: "HS256" })
      decoded.first
    rescue JWT::ExpiredSignature
      raise "Token has expired"
    rescue JWT::DecodeError => e
      raise "Invalid token: #{e.message}"
    end
end
```

Secret comes from Rails credentials (`rails credentials:edit` → add `jwt_secret_key: <random>`),
never from an env var or hardcoded constant.

### 10.3 `KioskAuthentication` concern — per-request validation + `token_version` revocation

`app/controllers/concerns/kiosk_authentication.rb`

```ruby
module KioskAuthentication
  extend ActiveSupport::Concern

  KIOSK_AUTH_COOKIE = :kiosk_jwt_token

  included do
    before_action :authenticate_kiosk_device
    before_action :set_organisation
  end

  private

  def authenticate_kiosk_device
    if session[:kiosk_preview_mode]
      preview_user_id = session[:kiosk_preview_user_id]
      session_record = Session.active.find_by(id: cookies.signed[:session_id])

      if session_record&.user_id == preview_user_id
        return true
      else
        reset_session   # regenerate session ID to prevent fixation
        redirect_to login_path, alert: "Please sign in to use kiosk preview."
        return
      end
    end

    token = extract_jwt_token

    unless token.present?
      if request.format.json?
        render json: { error: "Authorization required" }, status: :unauthorized
      else
        redirect_to kiosk_setup_path, alert: "Please authenticate to access kiosk. Click 'Start Kiosk' to authenticate."
      end
      return
    end

    begin
      payload = JwtService.decode(token)
      device_id = payload["device_id"]

      @device = Device.find_by(device_id: device_id)

      unless @device
        if request.format.json?
          render json: { error: "Device not found" }, status: :not_found
        else
          redirect_to kiosk_setup_path, alert: "Device not found. Please check your configuration."
        end
        return
      end

      unless @device.active?
        error_msg = "Device is #{@device.status}"
        if request.format.json?
          render json: { error: error_msg }, status: :forbidden
        else
          redirect_to kiosk_setup_path, alert: "#{error_msg}. Please contact your administrator."
        end
        return
      end

      unless @device.organisation&.active?
        if request.format.json?
          render json: { error: "Organisation is disabled" }, status: :forbidden
        else
          redirect_to kiosk_setup_path, alert: "This organisation has been disabled. Please contact your administrator."
        end
        return
      end

      # Reject tokens issued before the last key rotation or revocation.
      # Tokens without token_version are treated as invalid - they predate revocation support.
      token_version = payload["token_version"]
      if token_version.nil? || token_version.to_i != @device.token_version
        clear_kiosk_jwt_token
        if request.format.json?
          render json: { error: "Token has been invalidated. Please re-authenticate." }, status: :unauthorized
        else
          redirect_to kiosk_setup_path, alert: "Your session has been invalidated by an administrator. Please re-authenticate."
        end
        return
      end

      if @device.registered_ip.present?
        request_ip = request.remote_ip
        unless request_ip == @device.registered_ip
          Rails.logger.warn "IP mismatch for device #{@device.device_id}: expected #{@device.registered_ip}, got #{request_ip}"
          error_msg = "Device must authenticate from registered IP address"
          if request.format.json?
            render json: { error: error_msg }, status: :forbidden
          else
            redirect_to kiosk_setup_path, alert: "#{error_msg}. Please contact your administrator."
          end
          return
        end
      else
        @device.update(registered_ip: request.remote_ip)
        Rails.logger.info "Auto-captured IP #{request.remote_ip} for device #{@device.device_id}"
      end

      @device.touch_last_seen

      # Persist browser requests without growing the Rails session cookie.
      if cookies.encrypted[KIOSK_AUTH_COOKIE].blank? && token.present?
        write_kiosk_jwt_token(token)
      end

    rescue => e
      Rails.logger.error "JWT authentication failed: #{e.message}"
      clear_kiosk_jwt_token

      if request.format.json?
        render json: { error: "Invalid or expired token" }, status: :unauthorized
      else
        redirect_to kiosk_setup_path, alert: "Authentication expired. Please click 'Start Kiosk' to authenticate again."
      end
    end
  end

  def extract_jwt_token
    auth_header = request.headers["Authorization"]
    return auth_header.match(/\ABearer (.+)\z/)&.[](1) if auth_header.present?

    cookies.encrypted[KIOSK_AUTH_COOKIE].presence || session[:kiosk_jwt_token].presence
  end

  def write_kiosk_jwt_token(token)
    session.delete(:kiosk_jwt_token)
    cookies.encrypted[KIOSK_AUTH_COOKIE] = {
      value: token,
      expires: 24.hours.from_now,
      httponly: true,
      same_site: :strict,
      secure: Rails.env.production?
    }
  end

  def clear_kiosk_jwt_token
    session.delete(:kiosk_jwt_token)
    cookies.delete(KIOSK_AUTH_COOKIE)
  end

  def set_organisation
    if session[:kiosk_preview_mode]
      @organisation = Organisation.find_by(id: session[:kiosk_preview_organisation_id])
      unless @organisation
        session.delete(:kiosk_preview_mode)
        session.delete(:kiosk_preview_organisation_id)
        session.delete(:kiosk_preview_user_id)
        redirect_to root_path, alert: "Preview organisation not found. Please try again."
      end
      return
    end

    @organisation = @device&.organisation

    unless @organisation
      if request.format.json?
        render json: { error: "No organisation configured for this device" }, status: :unprocessable_entity
      else
        redirect_to kiosk_setup_path, alert: "No organisation configured for this device. Please contact your administrator."
      end
    end
  end

  def current_device
    @device
  end
end
```

**`token_version` revocation is the key trick worth carrying over**: instead of a JWT
blocklist/deny-list, every issued token embeds the device's `token_version` at issuance time.
Every request re-checks it against the device's *current* `token_version` column. Bumping that
integer (on key regeneration or revocation) instantly invalidates every previously issued token
for that device — no token storage, no blocklist table, just an integer compare. Device/org
`active?` are also re-checked on **every** request (not just at issuance), so disabling a device
mid-session takes effect immediately.

### 10.4 Device → JWT exchange endpoint (API clients)

`app/controllers/api/v1/device_auth_controller.rb`

```ruby
class Api::V1::DeviceAuthController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :verify_authenticity_token

  # POST /api/v1/device_auth
  def create
    device = Device.find_by(device_id: params[:device_id])

    unless device
      write_device_audit_log(nil, :device_auth_failure, { reason: "device_not_found", device_id_attempted: params[:device_id] })
      render json: { error: "Device not found" }, status: :not_found
      return
    end

    unless device.active?
      write_device_audit_log(device, :device_auth_failure, { reason: "device_#{device.status}" })
      render json: { error: "Device is #{device.status}" }, status: :forbidden
      return
    end

    unless device.organisation&.active?
      write_device_audit_log(device, :device_auth_failure, { reason: "organisation_disabled" })
      render json: { error: "Organisation is disabled" }, status: :forbidden
      return
    end

    unless device.authenticate_api_key(params[:api_key])
      write_device_audit_log(device, :device_auth_failure, { reason: "invalid_api_key" })
      render json: { error: "Invalid API key" }, status: :unauthorized
      return
    end

    if device.registered_ip.present?
      request_ip = request.remote_ip
      unless request_ip == device.registered_ip
        write_device_audit_log(device, :device_auth_failure, { reason: "ip_mismatch", registered_ip: device.registered_ip })
        render json: { error: "Device must authenticate from registered IP address" }, status: :forbidden
        return
      end
    else
      device.update(registered_ip: request.remote_ip)
    end

    device.touch_last_seen

    token = JwtService.encode(
      device_id: device.device_id,
      additional_claims: {
        organisation_id: device.organisation_id,
        organisation_name: device.organisation&.name,
        serial: device.serial_number,
        token_version: device.token_version
      }
    )

    write_device_audit_log(device, :device_auth_success, { device_id: device.device_id, organisation_id: device.organisation_id })

    render json: { token: token, device_id: device.device_id, expires_at: 24.hours.from_now }, status: :ok
  end

  private

  def write_device_audit_log(device, event_type, metadata)
    AuditLog.create!(
      user: nil, event_type: event_type, ip_address: request.remote_ip, user_agent: request.user_agent,
      organisation_id: device&.organisation_id, resource_type: device ? "Device" : nil, resource_id: device&.id,
      metadata: metadata
    )
  rescue => e
    Rails.logger.error "[AuditLog] #{e.class}: #{e.message} - event=#{event_type} device=#{device&.device_id}"
  end
end
```

CSRF is explicitly skipped here (it's a token/JSON API endpoint, no cookie-based session to
protect) — this is the **only** place in the app where `verify_authenticity_token` is skipped.

### 10.5 Browser-based kiosk setup (device stores its own credentials)

`app/controllers/kiosk/setup_controller.rb` — lets a physical kiosk tablet store its
`device_id`/`api_key`/`ods_code` in encrypted, 1-year cookies, then re-authenticate against
those stored credentials to mint a fresh JWT without re-typing them. Full source:

```ruby
class Kiosk::SetupController < ApplicationController
  allow_unauthenticated_access

  KIOSK_AUTH_COOKIE = :kiosk_jwt_token

  def index
    @device_id = cookies.encrypted[:kiosk_device_id]
    @is_configured = @device_id.present?

    token = kiosk_jwt_token

    if token.present?
      begin
        payload = JwtService.decode(token)
        @authenticated_device_id = payload["device_id"]
        @is_authenticated = true
      rescue
        @is_authenticated = false
        clear_kiosk_jwt_token
      end
    end
  end

  def configure
    device_id = params[:device_id]
    api_key = params[:api_key]
    ods_code = params[:ods_code]

    if device_id.blank? || api_key.blank? || ods_code.blank?
      redirect_to kiosk_setup_path, alert: "Device ID, API Key and ODS code are required"
      return
    end

    cookies.encrypted[:kiosk_device_id] = { value: device_id, expires: 1.year.from_now, httponly: true }
    cookies.encrypted[:kiosk_api_key]   = { value: api_key,   expires: 1.year.from_now, httponly: true }
    cookies.encrypted[:kiosk_ods_code]  = { value: ods_code,  expires: 1.year.from_now, httponly: true }

    redirect_to kiosk_setup_path
  end

  def authenticate
    device_id = cookies.encrypted[:kiosk_device_id]
    api_key = cookies.encrypted[:kiosk_api_key]
    ods_code = cookies.encrypted[:kiosk_ods_code]

    unless device_id.present? && api_key.present? && ods_code.present?
      redirect_to kiosk_setup_path, alert: "Kiosk not configured. Please enter device credentials."
      return
    end

    organisation = Organisation.find_by(ods_code: ods_code)
    unless organisation
      redirect_to kiosk_setup_path, alert: "Organisation not found. Please check your ODS code."
      return
    end

    device = Device.find_by(device_id: device_id, organisation_id: organisation.id)
    unless device
      redirect_to kiosk_setup_path, alert: "Device not found. Please check your credentials."
      return
    end

    unless device.active?
      redirect_to kiosk_setup_path, alert: "Device is #{device.status}. Please contact administrator."
      return
    end

    unless device.authenticate_api_key(api_key)
      AuditLog.create!(
        event_type: :device_auth_failure, ip_address: request.remote_ip, user_agent: request.user_agent,
        organisation_id: organisation.id, resource_type: "Device", resource_id: device.id,
        metadata: { device_id: device_id, reason: "invalid_api_key", path: "kiosk/setup" }
      )
      redirect_to kiosk_setup_path, alert: "Invalid API key. Please re-configure."
      return
    end

    if device.registered_ip.present?
      request_ip = request.remote_ip
      unless request_ip == device.registered_ip
        redirect_to kiosk_setup_path, alert: "Device must authenticate from registered IP address. Please contact your administrator."
        return
      end
    else
      device.update(registered_ip: request.remote_ip)
    end

    token = JwtService.encode(device_id: device.device_id, additional_claims: { token_version: device.token_version })
    write_kiosk_jwt_token(token)
    device.touch_last_seen

    redirect_to kiosk_root_path, notice: "Kiosk authenticated successfully!"
  end

  def clear
    cookies.delete(:kiosk_device_id)
    cookies.delete(:kiosk_api_key)
    cookies.delete(:kiosk_ods_code)
    clear_kiosk_jwt_token

    redirect_to kiosk_setup_path
  end

  def logout
    clear_kiosk_jwt_token
    redirect_to kiosk_setup_path, notice: "Logged out. Click 'Start Kiosk' to login again."
  end

  private

  def kiosk_jwt_token
    cookies.encrypted[KIOSK_AUTH_COOKIE].presence || session[:kiosk_jwt_token].presence
  end

  def write_kiosk_jwt_token(token)
    session.delete(:kiosk_jwt_token)
    cookies.encrypted[KIOSK_AUTH_COOKIE] = { value: token, expires: 24.hours.from_now, httponly: true, same_site: :strict, secure: Rails.env.production? }
  end

  def clear_kiosk_jwt_token
    session.delete(:kiosk_jwt_token)
    cookies.delete(KIOSK_AUTH_COOKIE)
  end
end
```

Note `#logout` clears just the JWT (keeping stored device credentials for quick re-auth), while
`#clear` wipes everything including the stored device credentials.

### 10.6 Admin-side device revocation

`app/controllers/admin/devices_controller.rb` (excerpt):

```ruby
def regenerate_key
  new_key = SecureRandom.hex(32)
  @device.api_key = new_key
  @device.token_version += 1
  @device.save!
  log_audit(:device_key_regenerated, resource: @device, metadata: { device_id: @device.device_id })
  flash[:api_key] = new_key
  flash[:notice] = "API key regenerated. All active sessions for this device have been invalidated."
  redirect_to admin_device_path(@device)
end

def set_status
  new_status = params[:status]
  unless %w[active inactive revoked].include?(new_status)
    redirect_to admin_device_path(@device), alert: "Invalid status."
    return
  end
  if @device.status == "revoked" && new_status != "revoked"
    redirect_to admin_device_path(@device), alert: "A revoked device cannot be reactivated."
    return
  end
  old_status = @device.status
  @device.update!(status: new_status)
  @device.increment!(:token_version) if new_status == "revoked"
  log_audit(:device_updated, resource: @device, metadata: { device_id: @device.device_id, changed_fields: [ "status" ], old_status: old_status, new_status: new_status })
  redirect_to admin_device_path(@device), notice: "Device #{new_status}."
end
```

Note the one-way door: once a device is `revoked`, it can never be reactivated (`set_status`
explicitly blocks that transition) — a revoked device must be re-provisioned as a new device
record.

---

## 11. Waiting-display dual-mode authentication

The most novel mechanism: a public-facing "waiting room TV display" that a staff member sets up
once, after which the physical display (e.g. a browser on a lobby TV) keeps refreshing data for
**30 days** with no logged-in staff session.

`app/controllers/staff/waiting_view_controller.rb`

```ruby
class Staff::WaitingViewController < Staff::BaseController
  DISPLAY_TOKEN_COOKIE   = :waiting_display_token
  DISPLAY_TOKEN_DURATION = 30.days
  DISPLAY_TOKEN_PURPOSE  = "waiting_display"

  # Bypass the inherited staff auth chain - this screen uses dual-mode auth
  # (valid staff session OR long-lived display token).
  allow_unauthenticated_access
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :check_role_access, raise: false
  skip_before_action :ensure_admin_organisation_selected, raise: false
  skip_before_action :set_organisation, raise: false

  before_action :authenticate_for_display
  before_action :load_display_organisation

  def index
    stamp_display_token
    load_waiting_view_data
  end

  def poll
    load_waiting_view_data
    respond_to { |format| format.turbo_stream }
  end

  private

  def authenticate_for_display
    if resume_session
      @current_user = current_user  # required by current_organisation in RoleAuthentication
      return
    end
    return if valid_display_token?

    redirect_to login_path, alert: "Please sign in to set up this display."
  end

  def valid_display_token?
    raw = cookies.encrypted[DISPLAY_TOKEN_COOKIE]
    return false if raw.blank?

    payload = Rails.application.message_verifier(DISPLAY_TOKEN_PURPOSE).verify(raw)
    @display_org_id = payload[:org_id]
    true
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageExpired
    cookies.delete(DISPLAY_TOKEN_COOKIE)
    false
  end

  def load_display_organisation
    @organisation = if current_user
      current_organisation
    else
      Organisation.active.find_by(id: @display_org_id)
    end

    unless @organisation
      redirect_to login_path, alert: "Display session expired. Please sign in again."
    end
  end

  def stamp_display_token
    return unless current_user
    return if cookies.encrypted[DISPLAY_TOKEN_COOKIE].present?

    token = Rails.application.message_verifier(DISPLAY_TOKEN_PURPOSE)
              .generate({ org_id: @organisation.id }, expires_in: DISPLAY_TOKEN_DURATION)

    cookies.encrypted[DISPLAY_TOKEN_COOKIE] = {
      value: token, expires: DISPLAY_TOKEN_DURATION.from_now, httponly: true,
      same_site: :strict, secure: Rails.env.production?
    }
  end

  # ... load_waiting_view_data / filter_service_ids: business logic, not auth-relevant
end
```

Uses `ActiveSupport::MessageVerifier` — a **third, distinct** crypto primitive from the session
cookie and the device JWT — namespaced by the purpose string `"waiting_display"` so a token
minted for one purpose can never be replayed against a different verifier-purpose elsewhere in
the app, even though they all derive from the same `secret_key_base`. The token is deliberately
re-scoped to `Organisation.active` on every load, so disabling the org invalidates the display
immediately without needing to track/revoke the token itself.

This pattern generalizes to: **"long-lived unattended device auth that piggybacks on a
one-time authenticated stamping step"** — reusable anywhere you need a kiosk/display/TV screen
that a staff member configures once and then should keep working indefinitely without repeat
logins.

---

## 12. Audit logging

Not application-wide middleware — the concern is included per-controller-base-class where
needed (`Admin::BaseController`, `Manager::BaseController`, `Staff::BaseController`), and
security-critical events additionally call `AuditLog.create!` directly from concerns/models that
don't have access to the concern (e.g. `Authentication`, `SessionsController`, `User`,
`Api::V1::DeviceAuthController`, `Rack::Attack` subscriber).

### 12.1 `AuditLogging` concern

`app/controllers/concerns/audit_logging.rb`

```ruby
module AuditLogging
  extend ActiveSupport::Concern

  private

  def log_audit(event_type, resource: nil, organisation: nil, metadata: {})
    resolved_organisation = organisation || @current_organisation || @organisation

    AuditLog.create!(
      user:          current_user,
      event_type:    event_type,
      ip_address:    request.remote_ip,
      user_agent:    request.user_agent,
      organisation_id:   resolved_organisation&.id,
      resource_type: resource&.class&.name,
      resource_id:   resource&.id,
      metadata:      { controller: "#{params[:controller]}##{params[:action]}" }.merge(metadata)
    )
  rescue => e
    Rails.logger.error "[AuditLog] #{e.class}: #{e.message} - event=#{event_type} user=#{current_user&.id} resource=#{resource&.class}/#{resource&.id}"
  end

  def log_kiosk_audit(event_type, resource: nil, metadata: {})
    AuditLog.create!(
      user:          nil,
      event_type:    event_type,
      ip_address:    request.remote_ip,
      user_agent:    request.user_agent,
      organisation_id:   @organisation&.id,
      resource_type: resource&.class&.name,
      resource_id:   resource&.id,
      metadata:      { device_id: @device&.device_id, organisation_id: @organisation&.id }.merge(metadata)
    )
  rescue => e
    Rails.logger.error "[AuditLog] #{e.class}: #{e.message} - event=#{event_type} device=#{@device&.device_id}"
  end
end
```

Every call is wrapped in `rescue` so a logging failure (e.g. a DB blip) never breaks the
request it's trying to audit — audit logging is best-effort, never load-bearing for the
request's success.

### 12.2 `AuditLog` model

`app/models/audit_log.rb`

```ruby
class AuditLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :organisation, optional: true

  serialize :metadata, coder: JSON

  enum :event_type, {
    audit_log_viewed: "audit_log_viewed",
    login_success: "login_success",
    login_failure: "login_failure",
    two_factor_challenge_sent: "two_factor_challenge_sent",
    two_factor_success: "two_factor_success",
    two_factor_failure: "two_factor_failure",
    totp_enabled: "totp_enabled",
    totp_disabled: "totp_disabled",
    totp_email_fallback_requested: "totp_email_fallback_requested",
    logout: "logout",
    password_change: "password_change",
    session_created: "session_created",
    session_destroyed: "session_destroyed",
    account_locked: "account_locked",
    account_unlocked: "account_unlocked",
    user_created: "user_created",
    user_updated: "user_updated",
    user_deleted: "user_deleted",
    user_archived: "user_archived",
    user_viewed: "user_viewed",
    password_reset_by_admin: "password_reset_by_admin",
    password_reset_requested: "password_reset_requested",
    password_reset_link_sent: "password_reset_link_sent",
    password_reset_completed: "password_reset_completed",
    password_reset_failed: "password_reset_failed",
    # ... plus ~50 more business-event types (organisation/service/device/notification CRUD,
    # queue/appointment events, subject-access-request events) — see live enum for full list.
    rate_limit_triggered: "rate_limit_triggered",
    admin_access_blocked: "admin_access_blocked"
  }

  validates :event_type, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_organisation, ->(organisation) { where(organisation_id: organisation) }
  scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  scope :security_events, -> { where(event_type: %w[login_failure account_locked rate_limit_triggered admin_access_blocked password_reset_requested password_reset_link_sent password_reset_completed password_reset_failed]) }
  scope :device_events, -> { where(event_type: %w[device_auth_success device_auth_failure]) }

  def username
    metadata&.dig("username") || user&.username
  end
end
```

Design notes for porting: `event_type` is a plain string-backed enum kept in one central place —
add new event names here as new sensitive actions are introduced. `resource_type`/`resource_id`
form a lightweight polymorphic pointer (not a real `belongs_to :resource, polymorphic: true`,
just two plain columns) to whatever record the action affected, without requiring that record's
class to declare an inverse association. `metadata` is a serialized JSON text column — flexible
schema per event type, at the cost of not being queryable by field without `LIKE`/JSON functions
(see the `LIKE` dedup query in `PasswordExpiryNotificationJob`, §6.4, as an example of that
tradeoff in practice).

---

## 13. General security hardening

### 13.1 `ApplicationController` — top-level wiring

`app/controllers/application_controller.rb`

```ruby
class ApplicationController < ActionController::Base
  include Authentication
  include PasswordResetEnforcement
  protect_from_forgery with: :exception

  before_action :check_maintenance_mode
  before_action :enforce_admin_ip_allowlist

  private

  MAINTENANCE_FILE = Rails.root.join("storage/maintenance_mode.json")

  def enforce_admin_ip_allowlist
    return unless current_user&.admin?
    allowed_ips = ENV.fetch("ADMIN_ALLOWED_IPS", "").split(",").map(&:strip)
    return if allowed_ips.empty?
    return if allowed_ips.include?(request.remote_ip)

    AuditLog.create!(user: current_user, event_type: :admin_access_blocked, ip_address: request.remote_ip,
      user_agent: request.user_agent, metadata: { path: request.path, method: request.method })
    reset_session
    redirect_to login_path, alert: "Access denied: your IP address is not permitted."
  end

  def check_maintenance_mode
    return unless File.exist?(MAINTENANCE_FILE)
    return if controller_path.start_with?("sessions")  # allow login
    return if controller_path.start_with?("admin/")    # admins pass through
    return if current_user&.admin?

    config = JSON.parse(File.read(MAINTENANCE_FILE)) rescue {}
    return unless config["enabled"]

    @maintenance_message = config["message"]
    render "maintenance/index", layout: "maintenance", status: :service_unavailable
  end
end
```

`protect_from_forgery with: :exception` is the strict Rails default (raises on a missing/invalid
CSRF token) — the **only** place it's skipped anywhere in the codebase is the device-auth JSON
API endpoint (§10.4), which is a deliberate, narrow exception, not a broad policy.

**Admin IP allowlisting is layered twice**: once here at the controller level (any request from
an admin *user*, any path) and again at the Rack::Attack middleware level (any request to
`/admin*`, regardless of whether it resolves to a user yet) — see §13.3. Belt-and-braces: the
middleware layer blocks before Rails routing even runs; the controller layer catches an admin
user hitting a non-`/admin`-prefixed route (e.g. `/dashboard`) from a disallowed IP.

### 13.2 Active Record Encryption

No explicit key configuration beyond Rails 8 defaults (`config.load_defaults 8.0` in
`config/application.rb`) — encryption keys (`active_record_encryption.primary_key`,
`deterministic_key`, `key_derivation_salt`) live in Rails credentials
(`rails credentials:edit`), never in plain env vars or source.

```ruby
# User
encrypts :first_name
encrypts :last_name
encrypts :email, deterministic: true    # deterministic → uniqueness/find_by still work
encrypts :username, deterministic: true
encrypts :totp_secret                   # non-deterministic — no lookups needed on this field
```

`ServiceRequest` similarly encrypts `first_name`, `last_name`, `dob` (deterministic —
searchable), `postcode`, `description`. Rule of thumb: **deterministic** encryption only where a
DB-level uniqueness constraint or a `find_by` lookup is required on that field; everything else
uses non-deterministic (randomized IV) encryption for stronger confidentiality.

A commented-out escape hatch exists for a migration window if introducing encryption on an
existing unencrypted dataset:

```ruby
# Allow reading legacy unencrypted values from before encryption was introduced.
# Once all existing production records have been re-encrypted this can be removed.
# config.active_record.encryption.support_unencrypted_data = true
```

### 13.3 Rack::Attack — request throttling & IP blocklisting

`config/initializers/rack_attack.rb`

```ruby
ADMIN_ALLOWED_IPS = ENV.fetch("ADMIN_ALLOWED_IPS", "").split(",").map(&:strip).freeze

class Rack::Attack
  blocklist("admin/ip_allowlist") do |req|
    req.path.start_with?("/admin") && ADMIN_ALLOWED_IPS.any? && !ADMIN_ALLOWED_IPS.include?(req.ip)
  end

  throttle("logins/username", limit: 5, period: 20.minutes) do |req|
    req.params["username"].to_s.downcase.presence if req.path == "/login" && req.post?
  end

  throttle("logins/ip", limit: 10, period: 20.minutes) do |req|
    req.ip if req.path == "/login" && req.post?
  end

  throttle("device_auth/ip", limit: 10, period: 5.minutes) do |req|
    req.ip if req.path == "/api/v1/device_auth" && req.post?
  end

  throttle("device_auth/device_id", limit: 5, period: 5.minutes) do |req|
    req.params["device_id"].to_s.downcase.presence if req.path == "/api/v1/device_auth" && req.post?
  end

  throttle("kiosk/setup/authenticate/ip", limit: 5, period: 5.minutes) do |req|
    req.ip if req.path == "/kiosk/setup/authenticate" && req.post?
  end

  # ... several more per-route throttles for kiosk/public-portal/contact-form endpoints ...

  # Key on IP — req.session is not decrypted at Rack middleware level so user_id is never present there
  throttle("password_changes/ip", limit: 5, period: 15.minutes) do |req|
    req.ip if req.path == "/password" && req.patch?
  end

  self.blocklisted_responder = lambda do |req|
    [ 403, { "Content-Type" => "application/json" }, [ { error: "Forbidden" }.to_json ] ]
  end

  self.throttled_responder = lambda do |req|
    match_data = req.env["rack.attack.match_data"]
    now = match_data[:epoch_time]
    reset_time = now + (match_data[:period] - now % match_data[:period])
    retry_after_seconds = reset_time - now
    retry_after_minutes = (retry_after_seconds / 60.0).ceil

    headers = {
      "Content-Type" => "application/json",
      "RateLimit-Limit" => match_data[:limit].to_s,
      "RateLimit-Remaining" => "0",
      "RateLimit-Reset" => reset_time.to_s,
      "Retry-After" => retry_after_seconds.to_s
    }

    body = {
      error: "Too many requests",
      message: "You've exceeded the maximum number of attempts. Please try again in #{retry_after_minutes} minutes.",
      retry_after_minutes: retry_after_minutes,
      retry_after_seconds: retry_after_seconds,
      reset_at: Time.at(reset_time).iso8601
    }.to_json

    [ 429, headers, [ body ] ]
  end
end

ActiveSupport::Notifications.subscribe("rack.attack") do |_name, _start, _finish, _id, payload|
  req        = payload[:request]
  match_type = req.env["rack.attack.match_type"]
  next unless %i[throttle blocklist].include?(match_type)

  matched    = req.env["rack.attack.matched"]
  match_data = req.env["rack.attack.match_data"] || {}
  event_type = match_type == :blocklist ? "admin_access_blocked" : "rate_limit_triggered"

  Rails.logger.warn("[SECURITY] #{event_type} | rule=#{matched} | ip=#{req.ip} | path=#{req.path} | ua=#{req.env['HTTP_USER_AGENT']}")

  AuditLog.create!(
    user: nil, event_type: event_type, ip_address: req.ip, user_agent: req.env["HTTP_USER_AGENT"],
    metadata: { rule: matched, path: req.path, method: req.request_method, limit: match_data[:limit], count: match_data[:count], period: match_data[:period] }.compact
  )
rescue => e
  Rails.logger.error "[AuditLog] rack.attack subscriber failed: #{e.class}: #{e.message}"
end
```

Every throttle/blocklist hit is both logged (`Rails.logger.warn`) **and** written to the same
`AuditLog` table used everywhere else — one unified security event stream, regardless of whether
the block happened in a controller or in Rack middleware.

Registered in `config/application.rb`:

```ruby
config.middleware.use Rack::Attack
```

### 13.4 Defense-in-depth headers, CSP, permissions policy

`config/application.rb`:

```ruby
config.action_dispatch.default_headers = config.action_dispatch.default_headers.merge(
  "Cross-Origin-Opener-Policy" => "same-origin",
  "Cross-Origin-Resource-Policy" => "same-origin",
  "X-Content-Type-Options" => "nosniff",
  "X-Frame-Options" => "DENY"
)
```

`config/initializers/content_security_policy.rb`:

```ruby
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    policy.connect_src :self
    policy.font_src    :self, :data
    policy.frame_src   :self
    policy.form_action :self
    policy.frame_ancestors :none
    policy.img_src :self, :data
    policy.manifest_src :self
    policy.media_src   :self
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self
    policy.worker_src  :blob, :self
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.hex(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
```

(Trim the `analytics.strixon.co.uk` / `cdn.jsdelivr.net` allowances shown in the live file —
those are project-specific third-party origins, not part of the reusable pattern.)

`config/initializers/permissions_policy.rb`:

```ruby
Rails.application.config.permissions_policy do |policy|
  policy.camera      :none
  policy.microphone  :none
  policy.geolocation :none
  policy.usb         :none
  policy.payment     :none
  policy.gyroscope   :none
  policy.accelerometer :none
  policy.fullscreen :self
end
```

### 13.5 Session store, SSL, log filtering

`config/initializers/session_store.rb`:

```ruby
# Keep the framework session cookie aligned with the stricter custom auth cookie.
Rails.application.config.session_store :cookie_store,
  key: "_rxterminal_rails_session",
  secure: Rails.env.production?,
  httponly: true,
  same_site: :strict
```

`config/environments/production.rb`:

```ruby
config.assume_ssl = true
config.force_ssl = true
```

`config/initializers/filter_parameter_logging.rb` — scrub sensitive params from logs (partial
match, so `otp` also catches params like `totp_code`):

```ruby
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]
```

### 13.6 Housekeeping job — expired session cleanup

`app/jobs/cleanup_expired_sessions_job.rb`

```ruby
class CleanupExpiredSessionsJob < ApplicationJob
  queue_as :default

  def perform
    count = Session.expired.count
    Session.cleanup_expired!

    Rails.logger.info "Cleaned up #{count} expired sessions"
  end
end
```

Not the primary enforcement mechanism (that's `Session.active` scoping + `check_session_expiry`,
§4.3/4.4, which act on every request) — this is a periodic GC pass, schedule it daily/hourly via
Solid Queue recurring tasks or cron.

### 13.7 Static analysis

`brakeman` runs with **zero suppressions** (no `.brakeman.ignore` file) — any finding surfaces on
every scan. Run it as part of CI, not just ad hoc.

---

## 14. Routes reference

```ruby
# Authentication routes
resource :session, only: [ :new, :create, :destroy ]
resource :password, only: [ :edit, :update ]
resources :password_resets, only: [ :new, :create, :edit, :update ], param: :token
resource :profile, only: [ :show, :edit, :update ], controller: "profile"
get    "profile/totp/new", to: "profile#new_totp",   as: :new_profile_totp
post   "profile/totp",     to: "profile#create_totp", as: :profile_totp
delete "profile/totp",     to: "profile#destroy_totp"
get "organisation_picker", to: "dashboard#organisation_picker", as: :organisation_picker
match "organisation_picker/select", to: "dashboard#select_organisation", as: :select_organisation, via: [ :get, :post ]

# Convenience aliases
get  "login", to: "sessions#new"
post "login", to: "sessions#create"
get  "login/two_factor",                to: "sessions#two_factor",                as: :two_factor_login
post "login/two_factor",                to: "sessions#verify_two_factor",         as: :verify_two_factor_login
post "login/two_factor/resend",         to: "sessions#resend_two_factor",         as: :resend_two_factor_login
post "login/two_factor/email_fallback", to: "sessions#email_two_factor_fallback", as: :email_two_factor_fallback_login
delete "logout", to: "sessions#destroy"

# Device API auth
namespace :api do
  namespace :v1 do
    post "device_auth", to: "device_auth#create"
  end
end

# Kiosk setup (browser-stored device credentials)
get   "kiosk/setup",            to: "kiosk/setup#index"
post  "kiosk/setup/configure",  to: "kiosk/setup#configure"
post  "kiosk/setup/authenticate", to: "kiosk/setup#authenticate"
match "kiosk/setup/clear",      to: "kiosk/setup#clear",  via: [ :get, :post ]
match "kiosk/setup/logout",     to: "kiosk/setup#logout", via: [ :get, :post ]

# Namespaced portals — each with role-checked resources
namespace :admin do
  resources :devices do
    member { post :regenerate_key; post :clear_ip; post :set_status }
  end
  resources :users do
    member { post :reset_password; post :send_reset_link; post :unlock; post :disable }
  end
  # ... orgs, services, notifications, audit_logs, etc.
end
namespace :manager do
  # ... services, staff, calendars, analytics, kiosk config
end
namespace :staff do
  # ... queue, appointments, waiting_view
end

# Public multi-tenant portal — placed LAST so reserved namespace words never
# get swallowed by the slug wildcard.
scope "/:organisation_slug",
  constraints: { organisation_slug: /(?!admin|manager|staff|kiosk|api|health|assets|packs|demo|login|logout|blog)[a-z0-9][a-z0-9\-]*[a-z0-9]/ },
  module: :public do
  # booking, walk-in, check-in
end
```

---

## 15. Porting checklist

1. **Gems**: add `bcrypt`, `jwt`, `rotp`, `rqrcode`, `rack-attack`, `brakeman` (dev) to the
   Gemfile (§2). Add `require "rotp"` / `require "rqrcode"` to `config/application.rb`.
2. **Credentials**: run `rails credentials:edit` and add a `jwt_secret_key` (only needed if
   porting the kiosk/device JWT system). Active Record Encryption keys are auto-generated on
   `rails db:encryption:init` if not already present.
3. **Migrations**: create `sessions`, `admin_two_factor_challenges`, `password_histories`,
   `password_reset_tokens`, `devices` (if using kiosk auth), and `audit_logs` tables per §3. Add
   the TOTP/lockout/password-lifecycle columns to `users` (`failed_login_attempts`,
   `locked_until`, `password_changed_at`, `password_expires_at`, `password_reset_required`,
   `totp_enabled_at`, `totp_last_used_at`, `totp_secret`, `pii_redacted_at` if you have a PII
   redaction flow, `last_sign_in_at`).
4. **Models**: `User` (with `encrypts`, password validations, TOTP methods, lockout methods),
   `Session`, `PasswordHistory`, `PasswordResetToken`, `AdminTwoFactorChallenge`, `AuditLog`,
   `Current`. If porting kiosk auth: `Device`.
5. **Controllers/concerns**: `Authentication`, `RoleAuthentication` (trim/adapt the
   multi-tenant bits if your project is single-tenant), `AuditLogging`,
   `PasswordResetEnforcement`, `SessionsController`, `PasswordsController`,
   `PasswordResetsController`, `ProfileController`. If porting kiosk: `KioskAuthentication`,
   `JwtService`, `Api::V1::DeviceAuthController`, `Kiosk::SetupController`.
6. **Mailers**: `TwoFactorMailer`, `PasswordResetMailer` (adapt sender name/branding).
7. **Jobs**: `CleanupExpiredSessionsJob`, `PasswordExpiryNotificationJob` — wire into your
   scheduler (Solid Queue recurring tasks, `whenever`, or plain cron).
8. **Initializers**: `rack_attack.rb` (adjust routes/limits to your app's actual endpoints),
   `content_security_policy.rb`, `permissions_policy.rb`, `session_store.rb`,
   `filter_parameter_logging.rb`.
9. **`ApplicationController`**: wire `include Authentication`, `include PasswordResetEnforcement`,
   `protect_from_forgery with: :exception`, and (optionally) the admin IP allowlist +
   maintenance-mode before_actions.
10. **Views**: login form, 2FA code-entry screen, profile show/edit, TOTP enrollment (QR SVG +
    manual key + password/code form), password edit form, password-reset request/edit forms.
11. **Env vars**: `ADMIN_ALLOWED_IPS` (optional, comma-separated) if using the admin IP
    allowlist.
12. **Verify end-to-end** once ported: register a user, log in (should hit 2FA — email fallback
    if TOTP not yet enrolled), enroll TOTP from `/profile`, log out, log back in with a TOTP
    code, trigger account lockout with 5 bad passwords, request + complete a password reset,
    trigger the 90-day/history/complexity password validations by trying to reuse or weaken a
    password, and (if porting kiosk auth) provision a device, authenticate it, then revoke it
    and confirm its JWT stops working immediately.
