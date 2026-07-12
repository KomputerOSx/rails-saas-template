Rails.application.routes.draw do
  # Health + internal endpoints must be outside the custom-domain catch-all.
  # kamal-proxy probes /up with a non-APP_HOST Host header; if the catch-all
  # wins first, SitesController returns 404 and the deploy never goes healthy.
  get "up" => "rails/health#show", as: :rails_health_check

  # Caddy on-demand TLS ask endpoint (internal Docker / localhost only).
  namespace :internal do
    get "domain_validations", to: "domain_validations#show"
  end

  # Custom domains serve a public org site (placeholder for future shopfront/booking).
  constraints CustomDomainConstraint do
    root to: "sites#show", as: :custom_domain_root
    get "*path", to: "sites#show", as: :custom_domain_catch_all
  end

  # --- Authentication ---
  resource :session, only: [ :new, :create, :destroy ], controller: "sessions"
  get    "login",  to: "sessions#new"
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  get  "login/two_factor",                to: "sessions#two_factor",                as: :two_factor_login
  post "login/two_factor",                to: "sessions#verify_two_factor",         as: :verify_two_factor_login
  post "login/two_factor/resend",         to: "sessions#resend_two_factor",         as: :resend_two_factor_login
  post "login/two_factor/email_fallback", to: "sessions#email_two_factor_fallback", as: :email_two_factor_fallback_login

  # --- OmniAuth (Google / GitHub) ---
  # The request phase (/auth/:provider) is handled directly by the OmniAuth::Builder
  # middleware (config/initializers/omniauth.rb) - only the callback needs a route.
  get "auth/:provider/callback", to: "omniauth_callbacks#create"

  resource :password, only: [ :edit, :update ], controller: "passwords"
  resources :password_resets, only: [ :new, :create, :edit, :update ], param: :token

  get  "signup", to: "registrations#new",    as: :new_registration
  post "signup", to: "registrations#create", as: :registration
  get  "confirmations/new", to: "confirmations#new",    as: :new_confirmation
  post "confirmations",     to: "confirmations#create", as: :confirmations

  resource :profile, only: [ :show, :update, :destroy ], controller: "profile"
  resource :billing, only: [ :show ], controller: "billing" do
    resource :setup_intent, only: [ :create ], controller: "billing/setup_intents"
    resource :payment_method, only: [ :create, :destroy ], controller: "billing/payment_methods"
    resource :subscription, only: [ :create, :destroy ], controller: "billing/subscriptions" do
      resource :resume, only: [ :create ], controller: "billing/subscription_resumes"
      resource :scheduled_change, only: [ :destroy ], controller: "billing/scheduled_changes"
    end
    resource :currency, only: [ :update ], controller: "billing/currencies"
    resource :billing_address, only: [ :update ], controller: "billing/billing_addresses"
    resource :promo_code, only: [ :create, :destroy ], controller: "billing/promo_codes"
  end
  get    "profile/totp/new",     to: "profile#new_totp",          as: :new_profile_totp
  post   "profile/totp",         to: "profile#create_totp",       as: :profile_totp
  delete "profile/totp",         to: "profile#destroy_totp"
  post   "profile/deletion_code", to: "profile#send_deletion_code", as: :profile_deletion_code
  patch  "profile/email_preferences", to: "profile#update_email_preferences", as: :profile_email_preferences

  resource :profile_email_change, only: [ :new, :create, :destroy ], controller: "email_changes", path: "profile/email_change"
  post "profile/email_change/confirm_old", to: "email_changes#confirm_old", as: :confirm_old_profile_email_change
  post "profile/email_change/confirm_new", to: "email_changes#confirm_new", as: :confirm_new_profile_email_change

  root "home#index"
  get "dashboard" => "dashboard#index"

  # --- Onboarding ---
  get   "onboarding",       to: "onboarding#show",   as: :onboarding
  get   "onboarding/:step", to: "onboarding#show",   as: :onboarding_step
  patch "onboarding/:step", to: "onboarding#update"
  post  "onboarding/skip",  to: "onboarding#skip",   as: :skip_onboarding

  resources :notification_recipients, only: [ :index, :destroy ] do
    member do
      patch :mark_read
    end
    collection do
      patch :mark_all_read
    end
  end

  namespace :admin do
    root to: "dashboard#index"
    resources :users, only: [ :index, :show, :update ] do
      resource :user_role, only: [ :create, :destroy ], controller: "user_roles"
      member do
        patch :disable
        patch :enable
        post  :send_reset_link
      end
    end
    resources :roles
    resources :permissions
    resources :features, only: [ :index, :edit, :update ]
    resources :audit_logs, only: [ :index, :show ]
    resources :notifications, only: [ :index, :new, :create ] do
      member do
        patch :withdraw
      end
    end
    resources :email_campaigns, only: [ :index, :new, :create, :show, :edit, :update, :destroy ] do
      member do
        post :deliver
        get  :recipients
      end
    end
    resources :email_campaign_images, only: [ :create ]
    resource :maintenance_mode, only: [ :edit, :update ], controller: "maintenance_mode" do
      post :force_logout_all
    end
    resources :price_migrations, only: [ :new, :create ]
    resources :organizations, only: [] do
      resource :grandfather, only: [ :create, :destroy ], controller: "organization_grandfathers"
    end
  end

  # --- Organization invitations (public acceptance endpoint) ---
  get  "invitations/:token",        to: "invitations#show",   as: :invitation
  post "invitations/:token/accept", to: "invitations#accept", as: :accept_invitation

  # --- Email preference center (public, unauthenticated - reached from an emailed unsubscribe link) ---
  get   "email_preferences/:token",           to: "email_preferences#show",   as: :email_preference
  patch "email_preferences/:token",           to: "email_preferences#update"
  post  "email_preferences/:token/one_click", to: "email_preferences#one_click", as: :one_click_email_preference

  # --- Org-facing members/invitations management (distinct from the system-scope Admin:: namespace) ---
  namespace :org do
    resource :organization, only: [ :update ], controller: "organizations"
    resource :custom_domain, only: [ :create, :destroy ], controller: "custom_domains"
    get "settings", to: "settings#index", as: :settings
    resources :members, only: [ :destroy ] do
      member do
        patch :promote
        patch :demote
        patch :promote_to_owner
        post  :send_promotion_code
        patch :demote_owner
        post  :send_owner_demotion_code
      end
      collection do
        delete :leave
      end
    end
    resources :invitations, only: [ :create, :destroy ]
    get   "features", to: "features#index",  as: :features
    patch "features", to: "features#update"
    post "switch", to: "switches#create", as: :switch
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
