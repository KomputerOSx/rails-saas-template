Rails.application.routes.draw do
  # --- Authentication ---
  resource :session, only: [ :new, :create, :destroy ], controller: "sessions"
  get    "login",  to: "sessions#new"
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  get  "login/two_factor",                to: "sessions#two_factor",                as: :two_factor_login
  post "login/two_factor",                to: "sessions#verify_two_factor",         as: :verify_two_factor_login
  post "login/two_factor/resend",         to: "sessions#resend_two_factor",         as: :resend_two_factor_login
  post "login/two_factor/email_fallback", to: "sessions#email_two_factor_fallback", as: :email_two_factor_fallback_login

  resource :password, only: [ :edit, :update ], controller: "passwords"
  resources :password_resets, only: [ :new, :create, :edit, :update ], param: :token

  resource :registration, only: [ :new, :create ], controller: "registrations"
  get  "confirmations/new", to: "confirmations#new",    as: :new_confirmation
  post "confirmations",     to: "confirmations#create", as: :confirmations

  resource :profile, only: [ :show, :update, :destroy ], controller: "profile"
  get    "profile/totp/new", to: "profile#new_totp",    as: :new_profile_totp
  post   "profile/totp",     to: "profile#create_totp", as: :profile_totp
  delete "profile/totp",     to: "profile#destroy_totp"

  resource :profile_email_change, only: [ :new, :create, :destroy ], controller: "email_changes", path: "profile/email_change"
  post "profile/email_change/confirm_old", to: "email_changes#confirm_old", as: :confirm_old_profile_email_change
  post "profile/email_change/confirm_new", to: "email_changes#confirm_new", as: :confirm_new_profile_email_change

  root "home#index"
  get "dashboard" => "dashboard#index"

  namespace :admin do
    root to: "dashboard#index"
    resources :users, only: [ :index, :show ] do
      resource :user_role, only: [ :create, :destroy ], controller: "user_roles"
    end
    resources :roles, only: [ :index, :show ]
    resources :audit_logs, only: [ :index, :show ]
  end

  # --- Organization invitations (public acceptance endpoint) ---
  get  "invitations/:token",        to: "invitations#show",   as: :invitation
  post "invitations/:token/accept", to: "invitations#accept", as: :accept_invitation

  # --- Org-facing members/invitations management (distinct from the system-scope Admin:: namespace) ---
  namespace :org do
    resource :organization, only: [ :update ], controller: "organizations"
    resources :members, only: [ :index, :destroy ] do
      member do
        patch :promote
        patch :demote
      end
      collection do
        delete :leave
      end
    end
    resources :invitations, only: [ :create, :destroy ]
    post "switch", to: "switches#create", as: :switch
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
