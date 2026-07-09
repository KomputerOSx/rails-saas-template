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

  # Organizations with an active subscription still on the given Stripe price id - shared by
  # Admin::PriceMigrationsController's preview and Billing::MigratePriceJob's actual run, so
  # both always agree on exactly who a migration would affect. Pay's `active?` is a Ruby-level
  # predicate (trial/active/not-yet-ended), not a DB column, so this filters in Ruby after a
  # plain processor_plan lookup - fine at this app's scale; a large subscriber base would want
  # a DB-level status filter instead.
  def self.on_stripe_price(price_id)
    Pay::Subscription.where(processor_plan: price_id).includes(:customer)
      .select(&:active?)
      .filter_map { |subscription| subscription.customer.owner if subscription.customer.owner_type == "Organization" }
      .uniq
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

  # --- Subscription lifecycle ---
  #
  # Policy implemented here (see docs/BILLING.md):
  # - First subscribe from Free: immediate, charged today - unless the org is eligible for the
  #   one-time Starter trial, in which case Stripe starts a 14-day trial ($0 today, card charged
  #   automatically at trial end).
  # - Upgrade (more expensive plan): applied immediately, prorated difference invoiced right now
  #   ("always_invoice" - also Pay's own default for swap, made explicit here so the policy
  #   doesn't silently change if the gem's default ever does).
  # - Downgrade (cheaper plan): scheduled via a Stripe Subscription Schedule to take effect at
  #   the end of the current period - the org keeps what it already paid for, and the next
  #   renewal invoice is simply the lower price. Held in pending_plan_* columns until the
  #   renewal webhook confirms the flip (see Billing::ReconcileOrganizationJob).

  TRIAL_PLAN_KEY = "starter"
  TRIAL_DAYS = 14

  # One trial per organization, ever - trial_used_at is set the moment a trial starts and is
  # never cleared, so cancelling mid-trial doesn't restore eligibility.
  def trial_eligible?(plan)
    plan.key == TRIAL_PLAN_KEY && trial_used_at.nil?
  end

  def pending_plan
    return nil if pending_plan_key.blank?
    Billing::Plans.find(pending_plan_key)
  end

  # Moves the org onto `plan` under the policy above. Returns :created, :trial_started,
  # :upgraded, or :downgrade_scheduled so callers can pick the right audit event/message.
  #
  # `promotion_code` (a Stripe promotion code id, e.g. "promo_..." - resolved from a
  # human-entered code by Billing::PromoCodesController) only applies on subscribe/upgrade,
  # which invoice immediately - a scheduled downgrade has no invoice to discount right now, so
  # it's silently not passed through there; the code stays available in the session for the
  # caller to use on a future subscribe/upgrade instead.
  def change_plan!(plan, promotion_code: nil)
    payment_method = payment_processor.default_payment_method
    raise ArgumentError, "no payment method on file" unless payment_method

    price_id = plan.resolved_stripe_price_id(billing_currency)
    discount_options = promotion_code.present? ? { discounts: [ { promotion_code: promotion_code } ] } : {}

    if current_plan.free?
      if trial_eligible?(plan)
        payment_processor.subscribe(plan: price_id, default_payment_method: payment_method.processor_id,
          quantity: 1, trial_period_days: TRIAL_DAYS, **discount_options)
        update!(trial_used_at: Time.current)
        :trial_started
      else
        payment_processor.subscribe(plan: price_id, default_payment_method: payment_method.processor_id,
          quantity: 1, **discount_options)
        :created
      end
    elsif plan.price_cents(billing_currency) > current_plan.price_cents(billing_currency)
      # A subscription managed by a schedule rejects direct updates - release any pending
      # downgrade before swapping.
      cancel_scheduled_downgrade! if scheduled_downgrade?
      payment_processor.subscription.swap(price_id, proration_behavior: "always_invoice", **discount_options)
      :upgraded
    else
      schedule_downgrade!(plan)
      :downgrade_scheduled
    end
  end

  # Cancels at period end (never immediately - the org keeps access until what they paid for
  # runs out, and can resume any time before then). Releases any pending downgrade first, since
  # cancel_at_period_end can't be set on a schedule-managed subscription. Returns the (mutated)
  # subscription so callers can read ends_at back without a stale, separately-fetched copy.
  def cancel_subscription!
    cancel_scheduled_downgrade! if scheduled_downgrade?
    subscription = payment_processor.subscription
    subscription.cancel
    subscription
  end

  def scheduled_downgrade?
    pending_plan_key.present? || stripe_subscription_schedule_id.present?
  end

  # Attaches a promotion code straight to the live subscription for an already-subscribed org
  # (as opposed to change_plan!'s discount_options, which only apply on a subscribe/upgrade
  # call). `discounts:` replaces whatever discounts were on the subscription, not merges with
  # them - fine here since only one code is ever tracked at a time (see PromoCodesController).
  def apply_promotion_code!(promotion_code)
    subscription = payment_processor.subscription
    raise ArgumentError, "no active subscription" unless subscription&.active?

    ::Stripe::Subscription.update(subscription.processor_id, discounts: [ { promotion_code: promotion_code } ])
  rescue ::Stripe::StripeError => e
    raise Pay::Stripe::Error, e
  end

  # Strips any discount from the live subscription - the counterpart to apply_promotion_code!.
  def remove_promotion_code!
    subscription = payment_processor.subscription
    return unless subscription&.active?

    ::Stripe::Subscription.update(subscription.processor_id, discounts: [])
  rescue ::Stripe::StripeError => e
    raise Pay::Stripe::Error, e
  end

  # Live preview of the next invoice Stripe will actually generate for this subscription -
  # reflects whatever discounts currently apply, unlike the plan's static list price. Nil (and
  # the caller falls back to the static price) if there's nothing upcoming or the preview call
  # fails - this is a "nice to have" display, not something that should ever break the page.
  def upcoming_invoice_preview
    subscription = payment_processor&.subscription
    return nil unless subscription&.active? && !subscription.on_grace_period?

    ::Stripe::Invoice.create_preview(customer: payment_processor.processor_id, subscription: subscription.processor_id)
  rescue ::Stripe::StripeError
    nil
  end

  # Wraps the live subscription in a Stripe Subscription Schedule whose current phase ends at
  # the period end, followed by one billing cycle on the cheaper price; end_behavior "release"
  # then hands the subscription back to normal renewals at that price. Replaces any previously
  # scheduled downgrade.
  def schedule_downgrade!(plan)
    cancel_scheduled_downgrade! if scheduled_downgrade?

    schedule_id, effective_at = schedule_price_change!(plan.resolved_stripe_price_id(billing_currency))
    update!(pending_plan_key: plan.key, pending_plan_change_at: effective_at, stripe_subscription_schedule_id: schedule_id)
  rescue ::Stripe::StripeError => e
    raise Pay::Stripe::Error, e
  end

  # Releases the schedule on Stripe (subscription continues on its current price as if the
  # downgrade/price migration was never requested) and clears the local pending state.
  def cancel_scheduled_downgrade!
    # Fetch from the DB column first, fallback to checking Stripe directly in case
    # the local DB column was cleared but the schedule was left infinitely running.
    sub = payment_processor&.subscription
    schedule_id = stripe_subscription_schedule_id || (sub&.active? ? sub.as_stripe_subscription.schedule : nil)

    if schedule_id.present?
      begin
        ::Stripe::SubscriptionSchedule.release(schedule_id)
      rescue ::Stripe::InvalidRequestError
        # Already released/completed/canceled on Stripe's side - only the local pointer is stale.
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end
    end
    clear_pending_plan_change!
  end

  # Local-only cleanup, used once a scheduled downgrade/price migration has actually taken
  # effect (the renewal webhook confirms it - see Billing::ReconcileOrganizationJob).
  def clear_pending_plan_change!
    update!(pending_plan_key: nil, pending_plan_change_at: nil, stripe_subscription_schedule_id: nil, pending_price_cents: nil)
  end

  # --- Grandfathering & price migrations ---
  #
  # A grandfathered org is permanently excluded from Billing::MigratePriceJob - it keeps
  # whatever price it's already on until an admin explicitly un-grandfathers it. This is the
  # "keep some existing subscribers on their current price" half of a price increase; the
  # other half is #schedule_price_migration! below, which moves everyone else.

  def grandfathered?
    grandfathered_at.present?
  end

  def grandfather!
    update!(grandfathered_at: Time.current)
  end

  def ungrandfather!
    update!(grandfathered_at: nil)
  end

  # Same underlying mechanism as schedule_downgrade! (a Stripe Subscription Schedule taking
  # effect at the next renewal, no mid-cycle proration) but for a price change *within the
  # same plan* - e.g. migrating existing subscribers to a new, higher Price after a price
  # increase, driven by Billing::MigratePriceJob rather than a customer's own upgrade/downgrade
  # click. Deliberately refuses to run for a grandfathered org, or one that already has a plan
  # change (a downgrade) pending - a bulk price migration should never silently override either
  # of those without an admin looking at it first.
  def schedule_price_migration!(new_price_id:, new_price_cents:)
    raise ArgumentError, "organization is grandfathered" if grandfathered?
    raise ArgumentError, "a plan change is already pending" if pending_plan_key.present?

    cancel_scheduled_downgrade! if stripe_subscription_schedule_id.present?

    schedule_id, effective_at = schedule_price_change!(new_price_id)
    update!(pending_price_cents: new_price_cents, pending_plan_change_at: effective_at, stripe_subscription_schedule_id: schedule_id)
  rescue ::Stripe::StripeError => e
    raise Pay::Stripe::Error, e
  end

  private

  # Shared by schedule_downgrade! and schedule_price_migration! - both are "move the live
  # subscription to a different Price at its own next renewal, no proration" under the hood.
  # Returns [stripe_schedule_id, effective_at].
  def schedule_price_change!(new_price_id)
    subscription = payment_processor.subscription
    raise ArgumentError, "no active subscription" unless subscription&.active?

    schedule = ::Stripe::SubscriptionSchedule.create(from_subscription: subscription.processor_id)
    current_phase = schedule.phases.first

    ::Stripe::SubscriptionSchedule.update(schedule.id, {
      # We omit end_behavior: "release" and iterations: 1 to bypass the Stripe API validation quirk.
      # This leaves Phase 2 open-ended, which is completely fine.
      phases: [
        {
          items: current_phase.items.map { |item| { price: item.price, quantity: item.quantity } },
          start_date: current_phase.start_date,
          end_date: current_phase.end_date
        },
        { items: [ { price: new_price_id, quantity: 1 } ] }
      ]
    })

    [ schedule.id, Time.at(current_phase.end_date) ]
  end
end
