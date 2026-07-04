class Rack::Attack
  throttle("logins/email", limit: 5, period: 20.minutes) do |req|
    req.params["email"].to_s.downcase.presence if req.path == "/login" && req.post?
  end

  throttle("logins/ip", limit: 10, period: 20.minutes) do |req|
    req.ip if req.path == "/login" && req.post?
  end

  throttle("password_resets/ip", limit: 5, period: 10.minutes) do |req|
    req.ip if req.path == "/password_resets" && req.post?
  end

  throttle("password_resets/email", limit: 3, period: 10.minutes) do |req|
    req.params["email"].to_s.downcase.presence if req.path == "/password_resets" && req.post?
  end

  # Key on IP — req.session is not decrypted at Rack middleware level so user_id is never present there
  throttle("password_changes/ip", limit: 5, period: 15.minutes) do |req|
    req.ip if req.path == "/password" && req.patch?
  end

  # Registration: bounds both mass account-creation attempts and email-bombing a single address.
  throttle("registrations/ip", limit: 5, period: 20.minutes) do |req|
    req.ip if req.path == "/registration" && req.post?
  end

  throttle("registrations/email", limit: 3, period: 20.minutes) do |req|
    req.params.dig("user", "email").to_s.downcase.presence if req.path == "/registration" && req.post?
  end

  # Confirmation codes are only 6 digits — throttling by IP is the primary defense against
  # brute-forcing one within its expiry window (no per-record attempt lockout is kept).
  throttle("confirmations/ip", limit: 10, period: 10.minutes) do |req|
    req.ip if req.path == "/confirmations" && req.post?
  end

  throttle("email_change_confirm/ip", limit: 10, period: 10.minutes) do |req|
    req.ip if req.path.start_with?("/profile/email_change/confirm") && req.post?
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
  next unless match_type == :throttle

  matched    = req.env["rack.attack.matched"]
  match_data = req.env["rack.attack.match_data"] || {}

  Rails.logger.warn("[SECURITY] rate_limit_triggered | rule=#{matched} | ip=#{req.ip} | path=#{req.path} | ua=#{req.env['HTTP_USER_AGENT']}")

  AuditLog.create!(
    user: nil, event_type: :rate_limit_triggered, ip_address: req.ip, user_agent: req.env["HTTP_USER_AGENT"],
    metadata: { rule: matched, path: req.path, method: req.request_method, limit: match_data[:limit], count: match_data[:count], period: match_data[:period] }.compact
  )
rescue => e
  Rails.logger.error "[AuditLog] rack.attack subscriber failed: #{e.class}: #{e.message}"
end
