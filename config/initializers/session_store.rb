# :lax (not :strict) is required here: OmniAuth stores its CSRF `state` and PKCE
# `code_verifier` in this session, and the OAuth callback is a cross-site top-level
# GET navigation from the provider (e.g. accounts.google.com) — a Strict cookie
# wouldn't be sent on that request, silently breaking every OAuth login. The custom
# `session_id` auth cookie (app/controllers/concerns/authentication.rb) stays
# :strict since it's only ever set/read on same-origin requests.
Rails.application.config.session_store :cookie_store,
  key: "_windtunnel_session",
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax
