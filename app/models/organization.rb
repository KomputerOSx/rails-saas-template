class Organization < ApplicationRecord
  include FeatureToggleable

  SLUG_FORMAT = /\A[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?\z/
  RESERVED_SLUGS = %w[admin org invitations login logout password confirmations registration profile up rails].freeze

  # Pay::Customer#email delegates to owner.email (Pay::Customer#api_record_attributes reads it
  # unconditionally), so Organization needs its own #email even though we have no email column -
  # see #email below, which borrows the current owner's.
  #
  # name/address here fall back to the org's own name (no address) until the user explicitly
  # sets billing details via #sync_billing_details! - see there for how those then take over.
  pay_customer default_payment_processor: :stripe,
    stripe_attributes: ->(pay_customer) {
      organization = pay_customer.owner
      { name: organization.billing_name.presence || organization.name, address: organization.stripe_billing_address }.compact
    }

  serialize :features, coder: JSON
  after_initialize { self.features ||= {} }

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :membership_roles, through: :memberships
  has_many :organization_invitations, dependent: :destroy
  has_many :feature_organization_accesses, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
    format: { with: SLUG_FORMAT },
    length: { maximum: 63 },
    exclusion: { in: RESERVED_SLUGS }
  validates :preferred_currency, inclusion: { in: Billing::Plans::SUPPORTED_CURRENCIES }

  # Every user gets exactly one of these at signup - see ConfirmationsController#create.
  # Name/slug are derived from the email local-part since registration only collects
  # email/password (no name field exists at signup time).
  def self.create_personal_for!(user)
    base = slug_base_for(user)
    name = name_for(user)

    organization = begin
      create!(name: name, slug: generate_unique_slug(base))
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      # A concurrent signup claimed the same slug between our uniqueness check and
      # the write - retry once with a random suffix rather than failing the signup.
      create!(name: name, slug: "#{base}-#{SecureRandom.alphanumeric(6).downcase}")
    end
    membership = organization.memberships.create!(user: user)

    owner_role = Role.find_or_create_by!(scope: :app, name: Role::APP_OWNER) do |role|
      role.permanent = true
      role.description = "Organization owner - full control; cannot be removed while sole owner"
    end
    membership.grant_role!(owner_role)

    organization
  end

  def self.name_for(user)
    local_part = user.email.to_s.split("@").first.to_s
    words = local_part.gsub(/[^a-zA-Z0-9]+/, " ").strip
    words.present? ? words.split.map(&:capitalize).join(" ") : "My Organization"
  end

  def self.slug_base_for(user)
    local_part = user.email.to_s.split("@").first.to_s.downcase
    base = local_part.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    base.presence || "org"
  end

  def self.generate_unique_slug(base)
    slug = base
    suffix = 2

    while exists?(slug: slug)
      slug = "#{base}-#{suffix}"
      suffix += 1
    end

    slug
  end

  # Stripe Customer email (see Pay::Customer#email, which delegates here) - Organization has
  # no email column of its own, so we borrow the current owner's. Falls back gracefully if the
  # org somehow has no owner membership.
  def email
    memberships.joins(:roles).find_by(roles: { name: Role::APP_OWNER, scope: :app })&.user&.email
  end

  def current_plan
    subscription = payment_processor&.subscription
    return Billing::Plans::FREE unless subscription&.active?
    Billing::Plans.for_stripe_price(subscription.processor_plan) || Billing::Plans::FREE
  end

  # The currency prices/subscribing use everywhere on the billing page. Once actually
  # subscribed, this locks to whatever currency that subscription is really in (a Stripe
  # subscription can't swap to a Price in a different currency, so displaying/upgrading in
  # anything else would be misleading and would fail at Stripe anyway) - only while still on
  # Free does `preferred_currency` (the billing page's USD/GBP toggle) actually apply.
  def billing_currency
    subscription = payment_processor&.subscription
    return preferred_currency unless subscription&.active?
    Billing::Plans.currency_for_stripe_price(subscription.processor_plan) || preferred_currency
  end

  def member_limit
    current_plan.member_limit
  end

  def member_count_with_pending
    memberships.count + organization_invitations.outstanding.count
  end

  def at_member_limit?
    member_count_with_pending >= member_limit
  end

  def remaining_seats
    [ member_limit - member_count_with_pending, 0 ].max
  end

  def over_member_limit?
    over_member_limit_at.present?
  end

  # Stripe-shaped address hash built from the billing_address_* columns, or nil if none of
  # them are set (so we don't send Stripe an all-blank address object).
  def stripe_billing_address
    address = {
      line1: billing_address_line1, line2: billing_address_line2, city: billing_address_city,
      state: billing_address_state, postal_code: billing_address_postal_code, country: billing_address_country
    }
    address.values.all?(&:blank?) ? nil : address
  end

  # Persists the billing name/address locally and pushes them straight to the Stripe Customer
  # (what invoices' "Bill to" section actually reads from - not the payment method). Raises
  # Pay::Stripe::Error on failure; callers decide how to surface that.
  def sync_billing_details!(name:, address: {})
    update!(
      billing_name: name,
      billing_address_line1: address[:line1],
      billing_address_line2: address[:line2],
      billing_address_city: address[:city],
      billing_address_state: address[:state],
      billing_address_postal_code: address[:postal_code],
      billing_address_country: address[:country]
    )
    payment_processor.update_api_record(name: billing_name.presence || self.name, address: stripe_billing_address)
  end

  # Subscribes to `plan` (moving off Free) or swaps an already-active subscription to it
  # (upgrade/downgrade in place, prorated) - the org must already have a default payment
  # method. Returns :created or :updated so callers can pick the right audit event/message.
  def subscribe_to!(plan)
    payment_method = payment_processor.default_payment_method
    raise ArgumentError, "no payment method on file" unless payment_method

    price_id = plan.resolved_stripe_price_id(billing_currency)

    if current_plan.free?
      payment_processor.subscribe(plan: price_id, default_payment_method: payment_method.processor_id, quantity: 1)
      :created
    else
      payment_processor.subscription.swap(price_id)
      :updated
    end
  end
end
