Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    Rails.application.credentials.dig(:google, :client_id),
    Rails.application.credentials.dig(:google, :client_secret),
    scope: "email,profile"

  provider :github,
    Rails.application.credentials.dig(:github, :client_id),
    Rails.application.credentials.dig(:github, :client_secret),
    scope: "user:email"
end

# omniauth-rails_csrf_protection requires the request phase (/auth/:provider) to be a
# POST with a valid Rails CSRF token, mitigating login CSRF (CVE-2015-9284). Views must
# use `button_to`, not `link_to`, to hit these paths.
OmniAuth.config.allowed_request_methods = [ :post ]
OmniAuth.config.silence_get_warning = true

# Route failures (denied consent, provider errors) through our own controller so they
# get a normal Rails response (flash, layout) instead of OmniAuth's default Rack app.
# Deferred to `to_prepare` since the controller isn't autoloadable this early in boot.
Rails.application.config.to_prepare do
  OmniAuth.config.on_failure = OmniauthCallbacksController.action(:failure)
end
