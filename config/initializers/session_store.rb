# Keep the framework session cookie aligned with the stricter custom auth cookie.
Rails.application.config.session_store :cookie_store,
  key: "_windtunnel_session",
  secure: Rails.env.production?,
  httponly: true,
  same_site: :strict
