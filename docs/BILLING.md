# Billing

How Stripe subscription billing is wired into this template, how to configure it for a new
project, and how to adapt it for a single-user (non-team) app instead.

## Contents

1. [Overview](#1-overview)
2. [Plans](#2-plans)
3. [Stripe dashboard setup](#3-stripe-dashboard-setup)
4. [Credentials](#4-credentials)
5. [How it works](#5-how-it-works)
6. [Member limit enforcement](#6-member-limit-enforcement)
7. [Known limitations](#7-known-limitations)
8. [Testing](#8-testing)
9. [Adapting this for a single-user app](#9-adapting-this-for-a-single-user-app)

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
| Free | $0 | 1 |
| Starter | $10/mo | 5 |
| Growth | $30/mo | 20 |

The only thing a plan currently controls is `member_limit` (see
[Member limit enforcement](#6-member-limit-enforcement)). To add a feature-gated plan later,
extend the `Plan` `Data.define` in `app/models/billing/plans.rb` with more fields and read them
wherever `Organization#current_plan` is already consulted.

**Free is a local-only phantom plan** - there is no Stripe Product/Price for it, and no
`Pay::Subscription` row is ever created for an org on Free. `Organization#current_plan` returns
`Billing::Plans::FREE` simply when there's no active subscription. This means a brand-new org
never touches the Stripe API until its owner clicks "Upgrade."

**Displayed price vs. charged price are two separate sources of truth** - `price_cents` in
`app/models/billing/plans.rb` is only what the `/billing` UI *shows* ("$10.00/mo"); what Stripe
actually *charges* is whatever amount the Stripe Price object (`price_ids.starter` /
`price_ids.growth` in credentials) was created with. Nothing keeps these in sync automatically -
if you change one, update the other to match, or the UI will display a different amount than
what gets billed. `Plan#formatted_price` renders `price_cents` via `Pay::Currency.format`, so it
handles non-round amounts (e.g. `999` → `"$9.99"`) and any currency correctly - see `CURRENCY`
below.

**Currency**: `Billing::Plans::CURRENCY` (default `"usd"`) is a single constant every plan's
`formatted_price` uses. A Stripe Price is denominated in one fixed currency, so this can't vary
per plan/customer without setting up Stripe's multi-currency Prices feature (out of scope here -
this template assumes one currency for both tiers). If your Stripe account's prices aren't USD,
change this constant to match (e.g. `"gbp"`) - see the currency gotcha in
[Stripe dashboard setup](#3-stripe-dashboard-setup) below.

## 3. Stripe dashboard setup

Create the two paid Products/Prices by hand in the Stripe Dashboard (do this once per Stripe
account, in both test mode and live mode):

1. [dashboard.stripe.com/test/products](https://dashboard.stripe.com/test/products) → **+ Add
   product**. Create "Starter" with a recurring price of $10.00/month, and "Growth" with a
   recurring price of $30.00/month.
2. Copy each Price's id (starts with `price_...`, **not** the Product id) into
   `stripe.price_ids.starter` / `stripe.price_ids.growth` in credentials (see below).
3. [dashboard.stripe.com/test/webhooks](https://dashboard.stripe.com/test/webhooks) → **+ Add
   endpoint**, URL `https://yourdomain.com/pay/webhooks/stripe` (Pay auto-mounts this route -
   there is no controller to write). Subscribe to at minimum:
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`

   Copy the endpoint's signing secret into `stripe.signing_secret`.
4. Repeat steps 1-3 in live mode
   ([dashboard.stripe.com/products](https://dashboard.stripe.com/products), no `/test/` in the
   URL) before taking the app to production - test-mode and live-mode Products/Prices/webhook
   secrets are entirely separate.

A scripted `Stripe::Product.create`/`Stripe::Price.create` setup script was deliberately not
built here - for two fixed prices in a template, the dashboard is simpler and avoids a second
source of truth (code vs. dashboard) for objects a developer will look at once per project.

**Currency gotcha**: a Stripe Price is created in one specific currency, chosen in the dashboard
when you create it (defaults to your account's settlement currency). If your Stripe account's
country/settlement currency isn't USD (e.g. a UK account), creating a subscription against a
USD-denominated Price can be rejected outright depending on the payment method - the fix is to
create the Price in your account's actual currency (e.g. GBP) and use that price id, which is
also why `Billing::Plans::CURRENCY` needs to match (see [Plans](#2-plans) above). Switching to
Stripe's hosted Checkout would **not** avoid this - Checkout Sessions reference the exact same
fixed-currency Price object, so the mismatch is a Stripe account/Price configuration issue, not
something specific to this app's embedded-Elements UI.

## 4. Credentials

Stored in Rails encrypted credentials (`rails credentials:edit`), documented in
`config/credentials.example`:

```yaml
stripe:
  public_key: ""
  private_key: ""
  signing_secret: ""
  price_ids:
    starter: ""
    growth: ""
```

`private_key` and `signing_secret` are read automatically by the `pay` gem
(`Pay::Stripe.private_key` / `.signing_secret`) - no app code touches them directly.
`public_key` IS read directly by this app (`billing/_payment_method_dialog_content.html.erb`
inlines it as a data attribute for Stripe.js) since the embedded card form runs client-side -
make sure it's the real `pk_test_...`/`pk_live_...` **publishable** key, not a secret or
restricted key. `price_ids` is this app's own addition, read by `Billing::Plans::STARTER` /
`Billing::Plans::GROWTH`.

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
  `Organization#subscribe_to!`): if the org is on Free, calls
  `payment_processor.subscribe(plan:, default_payment_method:)`; if already on a paid plan, calls
  `subscription.swap(price_id)` to change the existing subscription's price in place (prorated)
  instead of creating a second one - both are Pay-provided `Pay::Stripe::Subscription` methods.
  (Note: Stripe's Subscription API param is `default_payment_method`, not `payment_method` -
  passing the latter gets rejected outright.)
  - **No card on file yet**: the Upgrade/Downgrade button opens the same payment-method dialog
    described above instead of posting directly, with the target plan attached as a Stimulus
    param (`data-stripe-payment-method-plan-param`). Once `stripe.confirmSetup()` succeeds, the
    plan key rides along as a hidden `plan` field on the same form post to
    `POST /billing/payment_method` - `PaymentMethodsController#create` saves the card *and* calls
    `organization.subscribe_to!` in the same request, so a brand-new org can add a card and
    subscribe in one step rather than being told to "add a payment method first" and having to
    find the button again. This response is always a full redirect (not a turbo_stream partial
    update), since subscribing changes more of the page (plan cards, member usage, cancel button)
    than the payment-method card alone.
- **Canceling** (`DELETE /billing/subscription`): `Rails.env.production?` decides which Pay
  method runs - `subscription.cancel` (marks `cancel_at_period_end: true`, access continues
  until the current period ends) in production, `subscription.cancel_now!` (ends immediately)
  everywhere else, specifically so this can be re-tested in dev without waiting out a billing
  cycle. See [Known limitations](#7-known-limitations) if this needs to be config-driven instead
  of environment-driven later.
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
- **Authorization**: gated by the pre-existing `app.billing.manage` RBAC permission (
  `config/rbac.yml`, granted only to the `owner` role), enforced via `BillingPolicy`
  (`app/policies/billing_policy.rb`) using the same `user.has_permission?(key, organization:)`
  idiom as every other org-scoped policy in this app.

## 6. Member limit enforcement

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

## 7. Known limitations

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
- **Cancellation timing is environment-driven** (`Rails.env.production?` in
  `Billing::SubscriptionsController#destroy`), not a configurable business rule. That's
  deliberate for a template baseline (immediate cancel makes the limit/downgrade flows easy to
  re-test locally without waiting out a billing cycle) but a real project may want this as an
  explicit setting instead of being tied to the Rails environment.
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

## 8. Testing

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

## 9. Adapting this for a single-user app

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
