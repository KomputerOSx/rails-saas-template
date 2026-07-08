# Billing

How Stripe subscription billing is wired into this template, how to configure it for a new
project, and how to adapt it for a single-user (non-team) app instead.

## Contents

1. [Overview](#1-overview)
2. [Plans](#2-plans)
3. [Stripe dashboard setup](#3-stripe-dashboard-setup)
4. [Credentials](#4-credentials)
5. [How it works](#5-how-it-works)
6. [Price increases: migrating existing subscribers vs. grandfathering](#6-price-increases-migrating-existing-subscribers-vs-grandfathering)
7. [Member limit enforcement](#7-member-limit-enforcement)
8. [Known limitations](#8-known-limitations)
9. [Testing](#9-testing)
10. [Adapting this for a single-user app](#10-adapting-this-for-a-single-user-app)

---

## 1. Overview

Billing is scoped to the **Organization**, not the User - every subscription, invoice, and
payment method belongs to an org, and every user who is a member of that org shares its plan.
This matches the rest of the app: an org is the unit of tenancy, membership, and permissions
(see `app/models/organization.rb`, `app/models/membership.rb`).

Integration uses the [`pay`](https://github.com/pay-rails/pay) gem as the Stripe abstraction
(`gem "pay"`, `gem "stripe"` in the Gemfile) rather than a hand-rolled Customer/Subscription
sync. Pay owns its own tables (`pay_customers`, `pay_subscriptions`, `pay_payment_methods`,
`pay_charges`, `pay_webhooks`), auto-mounts a webhook endpoint, and handles Stripe Checkout /
Billing Portal session creation.

All of it happens inline in the app's own UI on `/billing` - there is no redirect to a
Stripe-hosted Checkout or Billing Portal page. A card is collected via an embedded
[Stripe Elements](https://stripe.com/docs/payments/elements) Payment Element (in a modal
dialog, backed by a SetupIntent), saved as the org's default payment method, and reused for
every subscribe/upgrade/downgrade from then on - the card is only re-entered when the owner
explicitly clicks "Update payment method." Card data itself never touches the Rails server;
Stripe.js sends it directly to Stripe and the app only ever handles Stripe's opaque ids.

## 2. Plans

Defined in `app/models/billing/plans.rb` as a small, hand-editable registry - not a
database-driven plan builder, since a template only needs a couple of fixed tiers:

| Plan | Price | Member limit |
|---|---|---|
| Free | $0 / £0 | 1 |
| Starter | $9.99/mo or £9.99/mo | 5 |
| Growth | $29.99/mo or £29.99/mo | 20 |

The only thing a plan currently controls is `member_limit` (see
[Member limit enforcement](#7-member-limit-enforcement)). To add a feature-gated plan later,
extend the `Plan` `Data.define` in `app/models/billing/plans.rb` with more fields and read them
wherever `Organization#current_plan` is already consulted.

**Free is a local-only phantom plan** - there is no Stripe Product/Price for it, and no
`Pay::Subscription` row is ever created for an org on Free. `Organization#current_plan` returns
`Billing::Plans::FREE` simply when there's no active subscription. This means a brand-new org
never touches the Stripe API until its owner clicks "Upgrade."

**Displayed price vs. charged price are two separate sources of truth** - `Plan#prices` in
`app/models/billing/plans.rb` is only what the `/billing` UI *shows* ("$9.99/mo"); what Stripe
actually *charges* is whatever amount the corresponding Stripe Price object (`price_ids` in
credentials) was created with. Nothing keeps these in sync automatically - if you change one,
update the other to match, or the UI will display a different amount than what gets billed.
`Plan#formatted_price(currency)` renders the right currency's cents via `Pay::Currency.format`,
so it handles non-round amounts (e.g. `999` → `"$9.99"`) correctly.

### Multi-currency

Each plan holds a *separate* `Price` (cents + Stripe price id) per entry in
`Billing::Plans::SUPPORTED_CURRENCIES` (currently `usd` and `gbp`) - a Stripe Price is fixed to
one currency, so "switching currency" always means picking a different Price object, never
converting an amount. There is no live exchange-rate conversion here; both currencies' amounts
are set independently in `app/models/billing/plans.rb` (add a third currency by adding it to
`SUPPORTED_CURRENCIES` and giving every `Plan` a `Price` entry for it).

- **`Organization#preferred_currency`** (a real column, validated against
  `SUPPORTED_CURRENCIES`, defaults to `"usd"`) is the currency an org intends to subscribe in.
  The USD/GBP toggle on `/billing` (`PATCH /billing/currency`,
  `app/controllers/billing/currencies_controller.rb`) updates it.
- **`Organization#billing_currency`** is what the rest of the app actually reads (plan card
  prices, which Stripe Price gets used when subscribing/upgrading/downgrading). While on Free
  it's just `preferred_currency`. **Once subscribed, it locks to whatever currency that
  subscription is actually in** (resolved via `Billing::Plans.currency_for_stripe_price`),
  regardless of `preferred_currency` - a live Stripe subscription can't swap to a Price in a
  different currency, so displaying or upgrading in anything else would be misleading and would
  fail at Stripe anyway. The currency toggle itself is only rendered while `current_plan.free?`;
  once on a paid plan it's replaced with a static "Billed in USD"-style badge, and
  `CurrenciesController#update` refuses to change `preferred_currency` at that point.

## 3. Stripe dashboard setup

Create the two paid Products, each with **two Prices - one per currency** (do this once per
Stripe account, in both test mode and live mode):

1. [dashboard.stripe.com/test/products](https://dashboard.stripe.com/test/products) → **+ Add
   product**. Create "Starter" with a recurring price of $9.99/month, **then add a second price**
   on the same product for £9.99/month (GBP). Repeat for "Growth" at $29.99/month and £29.99/month.
   That's 2 products, 4 prices total.
2. Copy each Price's id (starts with `price_...`, **not** the Product id) into
   `stripe.price_ids.starter.usd` / `.gbp` and `stripe.price_ids.growth.usd` / `.gbp` in
   credentials (see below).
3. [dashboard.stripe.com/test/webhooks](https://dashboard.stripe.com/test/webhooks) → **+ Add
   endpoint**, URL `https://yourdomain.com/pay/webhooks/stripe` (Pay auto-mounts this route -
   there is no controller to write). Subscribe to the full set of events Pay's built-in handlers
   consume - **charges/invoices only appear in Billing History via these webhooks** (nothing is
   created synchronously in-app), so a missing event here means silently missing data:
   - `customer.subscription.created` / `customer.subscription.updated` /
     `customer.subscription.deleted` / `customer.subscription.trial_will_end`
   - `charge.succeeded` / `charge.refunded` / `charge.updated`
   - `payment_intent.succeeded`
   - `invoice.upcoming` / `invoice.updated` / `invoice.payment_action_required` /
     `invoice.payment_failed`
   - `payment_method.attached` / `payment_method.updated` /
     `payment_method.automatically_updated` / `payment_method.detached`
   - `customer.updated` / `customer.deleted`

   (For local development, `stripe listen --forward-to localhost:3000/pay/webhooks/stripe`
   forwards everything by default, which covers all of the above.)

   Copy the endpoint's signing secret into `stripe.signing_secret`.
4. Repeat steps 1-3 in live mode
   ([dashboard.stripe.com/products](https://dashboard.stripe.com/products), no `/test/` in the
   URL) before taking the app to production - test-mode and live-mode Products/Prices/webhook
   secrets are entirely separate.

A scripted `Stripe::Product.create`/`Stripe::Price.create` setup script was deliberately not
built here - for a handful of fixed prices in a template, the dashboard is simpler and avoids a
second source of truth (code vs. dashboard) for objects a developer will look at once per project.

**Currency gotcha this multi-currency setup avoids**: a Stripe Price is created in one specific
currency, chosen in the dashboard when you create it (defaults to your account's settlement
currency). If your Stripe account's country/settlement currency isn't USD (e.g. a UK account),
creating a subscription against a USD-denominated Price can be rejected outright depending on
the payment method. Having a real GBP Price (not just a USD one) for accounts outside the US is
exactly what this setup is for. Switching to Stripe's hosted Checkout would **not** have avoided
this on its own either way - Checkout Sessions reference the exact same fixed-currency Price
object, so the mismatch was always a Stripe account/Price configuration issue, not something
specific to this app's embedded-Elements UI.

## 4. Credentials

Stored in Rails encrypted credentials (`rails credentials:edit`), documented in
`config/credentials.example`:

```yaml
stripe:
  public_key: ""
  private_key: ""
  signing_secret: ""
  price_ids:
    starter:
      usd: ""
      gbp: ""
    growth:
      usd: ""
      gbp: ""
```

`private_key` and `signing_secret` are read automatically by the `pay` gem
(`Pay::Stripe.private_key` / `.signing_secret`) - no app code touches them directly.
`public_key` IS read directly by this app (`billing/_payment_method_dialog_content.html.erb`
inlines it as a data attribute for Stripe.js) since the embedded card form runs client-side -
make sure it's the real `pk_test_...`/`pk_live_...` **publishable** key, not a secret or
restricted key. `price_ids` is this app's own addition, read by `Billing::Plans::STARTER` /
`Billing::Plans::GROWTH`, one price id per supported currency.

## 5. How it works

- **`Organization` is the Pay billable** (`app/models/organization.rb`):
  `pay_customer default_payment_processor: :stripe`. `Current.organization.payment_processor`
  lazily creates a local `Pay::Customer` row on first access, and lazily creates the real Stripe
  Customer (one API call) the first time a SetupIntent is created - never on a plain page view.
- **Adding/updating a card** (`app/controllers/billing/setup_intents_controller.rb`,
  `POST /billing/setup_intent` + `app/controllers/billing/payment_methods_controller.rb`,
  `POST /billing/payment_method`): the "Update payment method" button opens a `<dialog>`
  (`app/views/billing/_payment_method_dialog_content.html.erb`) whose Stimulus controller
  (`app/javascript/controllers/stripe_payment_method_controller.js`) fetches a SetupIntent
  client secret, mounts a Stripe Elements Payment Element, and calls `stripe.confirmSetup()`
  client-side. On success it submits the resulting `setup_intent_id` to a normal Rails form,
  which syncs the payment method (`Pay::Stripe::PaymentMethod.sync_setup_intent`) and marks it
  default (`PaymentMethod#make_default!`) - both provided by Pay, no custom Stripe API calls.
- **Removing a card** (`app/controllers/billing/payment_methods_controller.rb`,
  `DELETE /billing/payment_method`): calls Pay's `PaymentMethod#detach` (removes it from Stripe)
  then destroys the local row - mirrors what Pay's own `payment_method.detached` webhook handler
  does, just synchronously instead of waiting on a webhook round-trip. **Blocked while subscribed
  to a paid plan** (`Organization#current_plan.free?` guard) so an org can't strand an active
  subscription with nothing to charge at renewal - cancel first, then remove the card.
- **Subscribing / upgrading / downgrading**
  (`app/controllers/billing/subscriptions_controller.rb`, `POST /billing/subscription`, backed by
  `Organization#change_plan!`, which returns `:created`/`:trial_started`/`:upgraded`/
  `:downgrade_scheduled` so the controller can pick the right message/audit event):
  - **First subscribe from Free**: `payment_processor.subscribe(plan:, default_payment_method:)` -
    charged today, unless the org is eligible for the one-time Starter free trial (see
    "Free trials" below). (Note: Stripe's Subscription API param is `default_payment_method`,
    not `payment_method` - passing the latter gets rejected outright.)
  - **Upgrade (more expensive plan)**: applied immediately via
    `subscription.swap(price_id, proration_behavior: "always_invoice")` - Stripe invoices the
    prorated difference for the remainder of the period right now, and the next renewal is at
    the new price. (`"always_invoice"` is also Pay's own default for `swap`; it's passed
    explicitly so the billing policy doesn't silently change if the gem's default ever does.)
    The Upgrade button's confirm dialog tells the user they'll be charged the difference today.
  - **Downgrade (cheaper plan)**: takes effect **at the end of the current period**, not
    immediately - the org keeps everything it already paid for, and the next renewal invoice is
    simply the lower price. Implemented with a Stripe Subscription Schedule
    (`Organization#schedule_downgrade!`): the current phase runs to `current_period_end`, one
    phase on the new price follows, then `end_behavior: "release"` hands the subscription back
    to normal renewals. The pending change is mirrored locally
    (`organizations.pending_plan_key/pending_plan_change_at/stripe_subscription_schedule_id`)
    to power the "Your plan changes to X on <date>" notice and a **"Keep current plan"** undo
    button (`DELETE /billing/subscription/scheduled_change`, which releases the schedule).
    `Billing::ReconcileOrganizationJob` clears the pending state once the renewal webhook
    confirms the price actually flipped. Upgrading or cancelling while a downgrade is pending
    releases the schedule first (a schedule-managed subscription rejects direct updates).
  - **No card on file yet**: the Upgrade/Downgrade button opens the same payment-method dialog
    described above instead of posting directly, with the target plan/name/price attached as
    Stimulus params (`data-stripe-payment-method-plan-param` etc.) - the dialog then shows what
    it's about to charge ("You'll be charged $9.99/mo...") and its submit button reads "Upgrade"
    instead of "Save card". Once `stripe.confirmSetup()` succeeds, the plan key rides along as a
    hidden `plan` field on the same form post to `POST /billing/payment_method` -
    `PaymentMethodsController#create` saves the card *and* calls `organization.change_plan!` in
    the same request, so a brand-new org can add a card and subscribe in one step rather than
    being told to "add a payment method first" and having to find the button again. This response
    is always a full redirect (not a turbo_stream partial update), since subscribing changes more
    of the page (plan cards, member usage, cancel button) than the payment-method card alone. The
    Payment Element is also explicitly configured with `fields: { billingDetails: { name: "always" } }`
    so the cardholder name field always shows - Stripe's own "auto" heuristic can omit it.
- **Canceling** (`DELETE /billing/subscription`, backed by `Organization#cancel_subscription!`):
  always cancels **at period end** (`subscription.cancel` → `cancel_at_period_end: true`) in
  every environment - the org keeps access to what it paid for until the period runs out, and
  nothing is ever cut off mid-cycle. Cancelling during a free trial ends at the trial's end and
  the card is never charged. Any pending scheduled downgrade is released first.
- **Resuming** (`POST /billing/subscription/resume`,
  `app/controllers/billing/subscription_resumes_controller.rb`): while a cancelled subscription
  is in its grace period (`subscription.on_grace_period?` - cancelled but not yet ended), the
  billing page shows a "cancelled, ends on <date>" banner with a **Resume subscription** button
  backed by Pay's `subscription.resume`, which flips `cancel_at_period_end` back off. Plan
  change buttons and the Cancel section are hidden during the grace period - resume first.
- **Free trials**: the **first** paid subscription an org ever starts gets a
  **14-day free trial if (and only if) it's the Starter plan** - card required up front, $0
  today, Stripe charges the card automatically when the trial ends
  (`payment_processor.subscribe(..., trial_period_days: 14)` in `Organization#change_plan!`).
  Eligibility is `Organization#trial_eligible?` (`trial_used_at IS NULL`); `trial_used_at` is
  stamped the moment a trial starts and never cleared, so it's strictly **one trial per
  organization, ever** - cancelling mid-trial doesn't restore it, and orgs that subscribed
  before this feature existed were backfilled as used. Trials are deliberately done in-app
  rather than via the Stripe Dashboard: dashboard trials would be manual per-customer and
  couldn't enforce the one-per-org rule. During a trial the billing page shows a "first charge
  on <date>" notice, and Growth is never trialed - upgrading from a Starter trial swaps
  immediately as usual.
- **Webhooks**: Pay auto-mounts `POST /pay/webhooks/stripe` and verifies the signature itself.
  `config/initializers/pay.rb` subscribes `Billing::SubscriptionSyncHandler` to
  `customer.subscription.created/updated/deleted`, which enqueues
  `Billing::ReconcileOrganizationJob` to recompute the org's over-limit flag and write an
  `AuditLog` entry (`subscription_created`/`subscription_updated`/`subscription_cancelled`). This
  is what keeps `/billing` correct if a subscription changes outside the app (e.g. a manual
  refund or edit in the Stripe Dashboard).
- **Downloading invoices**: the billing history table links each charge to
  `charge.stripe_invoice["invoice_pdf"]` when the charge is tied to a subscription invoice
  (Pay stores the full raw Stripe Invoice JSON on the charge via `store_accessor`), falling back
  to `charge.stripe_receipt_url` (Stripe's own hosted receipt) for one-off charges. No extra API
  call - both come from data Pay already synced.
- **Current plan resolution** (`Organization#current_plan`): no active `Pay::Subscription` →
  Free. Otherwise maps the subscription's Stripe price id back to a `Billing::Plans` entry,
  falling back to Free if the price id isn't recognized (e.g. a manually-created Stripe
  subscription on a price outside this registry).
- **Loading/double-submit protection**: every Stripe-backed button (Upgrade/Downgrade, Cancel
  subscription, Remove payment method) has `data-controller="loading-button"`
  (`app/javascript/controllers/loading_button_controller.js`), which disables the button and
  swaps its label to "Please wait..." the moment its form actually submits. These actions only
  fully settle once a webhook lands a moment later, so without this a second click before the
  page redirects/reloads could fire the same action twice (e.g. double-swap a plan). It listens
  on the *form's* native `submit` event rather than the button's `click`, so it still activates
  correctly when a `confirm-modal` defers the real submission until the user confirms. The
  embedded card dialog's own "Save card"/"Upgrade" button has its own equivalent disable/relabel
  logic built into `stripe_payment_method_controller.js#save`, since it's driven by a JS
  confirmation step rather than a plain form submit.
- **Authorization**: gated by the pre-existing `app.billing.manage` RBAC permission (
  `config/rbac.yml`, granted only to the `owner` role), enforced via `BillingPolicy`
  (`app/policies/billing_policy.rb`) using the same `user.has_permission?(key, organization:)`
  idiom as every other org-scoped policy in this app.

### Managing billing from the Stripe Dashboard

Day-to-day billing operations are meant to happen in the Dashboard, not in app code - the app
stays in sync via webhooks. What's safe and what isn't:

- **Refunds: safe.** Refund a charge in the Dashboard; the `charge.refunded` webhook updates
  `Pay::Charge#amount_refunded` and the billing history row shows a "Refunded" /
  "Partially refunded" badge.
- **Per-customer discounts: safe - use Coupons/promotion codes**, applied to the customer or
  subscription in the Dashboard, **or self-applied by the org** via the "Have a promo code?"
  field on the billing page (`Billing::PromoCodesController`). Entering a code resolves it to a
  Stripe promotion code id (`Stripe::PromotionCode.list(code:, active: true)`, checking the
  nested coupon's `valid` flag), and what happens next depends on billing state:
  - **Not yet subscribed (Free)**: the id is held in the session (not persisted - it's a
    checkout-time convenience, not organization state) until the next subscribe/upgrade, which
    passes it as `discounts: [{ promotion_code: id }]` to Stripe and then clears it.
  - **Already subscribed**: applied immediately to the live subscription
    (`Organization#apply_promotion_code!` → `Stripe::Subscription.update(id, discounts: [...])`)
    with no plan change - this is how to give an *existing* customer the same discount a new
    signup would get (e.g. "2 months off"), without them having to cancel/resubscribe. Removing
    it (`#remove_promotion_code!`) strips the discount back off the live subscription the same
    way. `discounts:` **replaces** whatever was there, not merges with it - fine here since only
    one code is ever tracked per org at a time.
  - Only applies to subscribe/upgrade/an already-active subscription (all have an invoice to
    discount); a *scheduled* downgrade has nothing to invoice right now, so an applied code is
    simply left in the session for a later subscribe/upgrade instead.
  - Whichever path, the subscription's price id doesn't change, so plan mapping and member
    limits are untouched, and the discounted amounts flow into synced invoices/charges
    automatically. (Plan cards keep showing the list price - only invoices reflect the discount.)
  - **Applying a coupon directly in the Dashboard on a customer mid-cycle** only affects the
    *next* invoice Stripe generates - it never retroactively touches an invoice already
    issued/paid for the current period. A coupon's `duration` (once / repeating N months /
    forever, set when the coupon itself was created) controls how many future invoices it
    applies to; Stripe tracks that automatically, no app code involved. To credit the *current*,
    already-invoiced period, use a refund or credit note instead - a discount alone won't do it.
  - The "Your next bill is $X on \<date\>" line on the billing page
    (`app/views/billing/_next_bill.html.erb`, `Organization#upcoming_invoice_preview`) calls
    Stripe's `Invoice.create_preview` live on every page load for an active subscription, so it
    always reflects whatever's actually about to be charged (including any discount just
    applied) rather than the plan's static list price. That's a deliberate extra API round-trip
    per page view in exchange for accuracy - it's rescued to fall back to the static price on
    any Stripe error, so a hiccup there never breaks the page.
- **Changing an individual subscription to a one-off custom Price: DON'T.** The app maps
  `processor_plan` (the Stripe price id) back to `Billing::Plans` to resolve the org's plan and
  member limit - an unknown price id falls back to **Free** (1-member limit + over-limit
  banner). Use a Coupon instead. As a safety net, `Billing::ReconcileOrganizationJob` logs a
  loud warning and stamps `unrecognized_price` into the audit log when it sees an active
  subscription on an unknown price.
- **Plan changes / cancels between this app's known Prices: safe** - the
  `customer.subscription.updated`/`.deleted` webhooks re-run the reconcile job and the app
  catches up on the next page load.

## 6. Price increases: migrating existing subscribers vs. grandfathering

Raising a plan's price (e.g. Starter $9.99 → $15.00) never touches subscribers on its own -
Stripe Prices are immutable and a subscription stays pinned to whatever Price it was created
with. Creating a new Price and pointing `Billing::Plans` at it (updating
`credentials.stripe.price_ids` **and** the plan's hardcoded `cents:` in
`app/models/billing/plans.rb`) only changes what *new* subscribers pay - existing ones are
grandfathered by default, permanently, simply because nothing ever moves them. Two admin-only
tools handle the rest, both gated behind the `system.billing.manage` permission
(`/admin` → "Price Migrations", `system_admin` gets it by baseline - **note**: on an
already-running database, `RbacRegistry` only attaches a role's baseline permissions the moment
that role is first created, so an existing `system_admin` won't pick up this new permission
automatically; grant it once via `/admin/roles`):

- **Migrating existing subscribers to the new price**
  (`Admin::PriceMigrationsController`, `/admin/price_migrations/new`): paste in the Plan,
  currency, and the *old* Stripe price id (no longer discoverable from `Billing::Plans` once
  credentials point at the new one) to preview exactly which organizations are currently on
  that price - split into those that will migrate and those already grandfathered. Confirming
  enqueues `Billing::MigratePriceJob`, which calls `Organization#schedule_price_migration!` for
  each eligible org - the same Stripe Subscription Schedule mechanism as a customer's own
  downgrade (`#schedule_downgrade!`), just moving to a different *Price* on the *same* Plan
  instead of a different Plan: the current phase runs to its natural end, then one phase on the
  new price, `end_behavior: "release"` handing the subscription back to normal renewals - no
  mid-cycle proration, no surprise charge. One organization's Stripe error doesn't stop the
  batch. Grandfathered organizations and any with a downgrade already pending are always
  skipped rather than silently overridden.
- **Grandfathering** (`Admin::OrganizationGrandfathersController`, buttons right on the
  migration preview page): `Organization#grandfather!`/`#ungrandfather!` toggle
  `grandfathered_at` - a durable account attribute, not tied to any one migration run. A
  grandfathered org is permanently excluded from `Billing::MigratePriceJob` until explicitly
  un-grandfathered.
- **The customer sees it coming**: while a price migration is pending, the billing page shows
  "Heads up - your price is changing to $X on \<date\>" (`pending_price_cents`, cleared by
  `Billing::ReconcileOrganizationJob` once the renewal webhook confirms the price actually
  flipped - the same `pending_plan_change_at`-based timing check used for downgrades). There's
  deliberately no customer-facing "keep my current price" button here - that's what
  grandfathering is for, and it's an admin decision, not a self-service one. **Advance notice
  to customers is on you** - this UI only shows *after* a migration has been scheduled; email
  your affected customers before running one, since raising a paying customer's price without
  warning is generally expected practice (and often a ToS/consumer-protection expectation)
  regardless of what the code allows.

## 7. Member limit enforcement

Every plan caps organization size. **Both accepted memberships and outstanding (unrevoked,
unexpired) invitations count toward the limit** - an owner can't send 10 invites on a 5-seat
plan and have them all land at once. `Organization#member_count_with_pending` /
`#at_member_limit?` / `#remaining_seats` implement this (`app/models/organization.rb`).

The limit is **hard-blocked** at every place a person can join an org:

- `Org::InvitationsController#create` - refuses to send a new invitation once the org is at its
  limit (flash message on both the `html` and `turbo_stream` formats).
- `OrganizationInvitation#accept!` - raises `OrganizationInvitation::MemberLimitReached` if
  accepting would put the org over its limit. This is checked **inside the model**, not in a
  controller, because there are three separate call sites that can accept an invitation
  (`InvitationsController#accept` for a direct accept, plus the login/signup/email-confirmation
  resumption flow in `InvitationResumption`) - putting the check in one shared place means none
  of them can be used to bypass it.

Note the accept-time check is intentionally looser than the invite-time check: an outstanding
invitation already reserves a seat, so *accepting* it doesn't add a new occupant and is only
blocked if the org has become genuinely oversubscribed since the invite was sent (e.g. a
downgrade or cancellation happened in between).

**Downgrades/cancellations are never intercepted** - they happen entirely inside Stripe's
Billing Portal, outside this app's control. Instead, `Billing::ReconcileOrganizationJob` runs
after every subscription webhook and sets `organizations.over_member_limit_at` if the org is now
over its (possibly lower) limit. This **never removes members automatically** - it only powers a
banner on `/billing` and continues to block new invites/accepts via the same guard above, until
an owner either upgrades again or removes members by hand.

## 8. Known limitations

Documented here rather than fixed, since they're reasonable trade-offs for a template baseline:

- **Accept-time race**: two people accepting the same invitation at the exact same instant could
  both pass the seat-limit check (TOCTOU). Not database-constraint-enforced.
- **Wasted seats**: an invitation left unaccepted for days still reserves a seat until it expires
  (7 days, `OrganizationInvitation::EXPIRY`) or is revoked. No cleanup job exists to free it
  early.
- **One differentiator only**: plans differ solely by member count. If a future project needs
  feature-gated tiers, extend `Billing::Plans::Plan` and check the new field wherever
  `current_plan` is read - the existing `FeatureToggleable` concern (`app/models/concerns/`) is
  a natural pairing for that.
- **Testing period-end flows locally takes patience**: cancels and downgrades both settle at the
  period end in every environment (no dev-only immediate cancel anymore, since Resume/undo make
  mid-cycle re-testing possible without it). To see a renewal-time price flip or a trial-end
  charge without waiting, use Stripe test clocks, or cancel via `cancel_now!` from a Rails
  console.
- **3D Secure / SCA is handled minimally**: the embedded card form uses `redirect: "if_required"`
  and a light `resumeAfterRedirect()` in the Stimulus controller for cards that do need an
  off-page authentication step, and `Billing::SubscriptionsController#create` rescues
  `Pay::ActionRequired`/`Pay::InvalidPaymentMethod` with a generic "update your payment method"
  message rather than a guided retry flow. Stripe's standard test cards (e.g. `4242 4242 4242
  4242`) never trigger this path, so it won't come up in day-to-day testing - budget time for a
  fuller SCA flow before processing real international cards at scale.
- **Only one saved card at a time**: adding a new card immediately replaces the previous default
  rather than keeping a card list. Fine for a template baseline; a real project wanting multiple
  saved payment methods would need a small UI list plus `Pay::PaymentMethod#detach`/`#make_default!`
  wired to each row instead of the single "Update payment method" dialog.

## 9. Testing

Tests use Minitest (this app has no RSpec/FactoryBot). No real Stripe API calls are made:

- **Model/limit logic** uses Pay's built-in `Pay::FakeProcessor`, which creates real
  `Pay::Subscription` rows with no network calls. `test/test_helper.rb` exposes
  `with_active_subscription(organization, plan)`, which grants a fake active subscription *and*
  stubs `Billing::Plans.for_stripe_price` (since Pay's price-id resolution needs a real Stripe
  price id, which test credentials don't have) - wrap any assertion that depends on the org's
  plan/seat limit in this block. See `test/models/organization_test.rb` and
  `test/integration/billing_limits_test.rb`.
- **SetupIntent/payment method sync** aren't modeled by the fake processor (they're inherently
  real-Stripe-API concerns), so those tests stub the Stripe SDK boundary directly
  (`Stripe::Customer.stub(:create, ...)`, `Stripe::SetupIntent.stub(:create, ...)`,
  `Pay::Stripe::PaymentMethod.stub(:sync_setup_intent, ...)`) rather than pulling in VCR/WebMock
  for a handful of narrow assertions. This requires the `minitest-mock` gem (minitest 6 split
  `Object#stub` out of the core gem - see the `Gemfile`'s `:test` group). See
  `test/integration/billing_setup_intents_test.rb` and `billing_payment_methods_test.rb`.
- **Subscribe/swap/cancel** (`test/integration/billing_subscriptions_test.rb`) run entirely
  against Pay's fake processor - `Pay::FakeProcessor::Subscription` implements `swap`/`cancel`/
  `cancel_now!` locally with no network calls, so these are tested for real rather than stubbed.
  `with_resolvable_price(plan)` (`test/test_helper.rb`) stubs `Billing::Plans.find` so a plan's
  `resolved_stripe_price_id` is non-blank without real Stripe price ids in test credentials.
- **Webhooks**: `Billing::SubscriptionSyncHandler` and `Billing::ReconcileOrganizationJob` are
  tested directly (`test/models/billing/subscription_sync_handler_test.rb`,
  `test/jobs/billing/reconcile_organization_job_test.rb`) rather than through a full
  `POST /pay/webhooks/stripe` round-trip - Pay's own built-in subscription-sync webhook handler
  calls out to the real Stripe API to fetch full subscription details on every event, which
  would require stubbing deep into Pay's internals for a full pipeline test. A lighter
  `test/integration/pay_webhooks_test.rb` confirms the endpoint is mounted and enforces
  signature verification, without touching that internal sync.

## 10. Adapting this for a single-user app

This template already behaves like a single-user app for anyone who never uses the invite flow:
`Organization.create_personal_for!` gives every user exactly one personal org 1:1 at signup, and
Free's 1-member limit means that org can never grow without an explicit upgrade. So for a
product like a personal weight-loss tracker - one account, one subscription, no teams - **keep
Organization as the hidden billing anchor** rather than moving Pay onto `User` directly. It
already carries the RBAC, slug, and `FeatureToggleable` scaffolding that a `User`-anchored
version would have to re-derive from scratch, and the entire billing implementation in this file
works completely unchanged.

To turn this into a single-user variant:

- **Hide, don't remove**, the multi-tenant UI: the `namespace :org do resources :members,
  :invitations ... end` routes/controllers/views (org switching, member management, invite
  forms) - a single-user app never needs any of it.
- `app/controllers/concerns/current_organization.rb` needs no change - it already resolves to
  the user's one personal org.
- Remove "Organization Settings" / member list / invite form from the nav and settings pages.
- Leave the `Role`/`Membership`/`Permission` tables and models alone rather than tearing them
  out - they become unused infrastructure, not a correctness problem, and ripping them out would
  touch far more of the app (every Pundit policy, `Current.organization`, every `org/`
  controller) than hiding a few UI surfaces.
- **The one real gap**: this template's only paid-tier differentiator is seat count, which is
  meaningless once there's only ever one seat. A single-user variant needs a different upsell
  axis before Starter/Growth pricing means anything - e.g. usage limits or feature flags via the
  existing `FeatureToggleable` concern. Decide that axis before reusing these two price points as-is.
