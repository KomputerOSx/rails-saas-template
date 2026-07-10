# Billing

How Stripe subscription billing is wired into this template, how to configure it for a new
project, and how to adapt it for a single-user (non-team) app instead.

## Contents

- [Billing](#billing)
  - [Contents](#contents)
  - [1. Overview](#1-overview)
  - [2. Plans](#2-plans)
    - [Multi-currency](#multi-currency)
  - [3. Stripe dashboard setup](#3-stripe-dashboard-setup)
  - [4. Credentials](#4-credentials)
  - [5. How it works](#5-how-it-works)
    - [Managing billing from the Stripe Dashboard](#managing-billing-from-the-stripe-dashboard)
  - [6. Price increases: migrating existing subscribers vs. grandfathering](#6-price-increases-migrating-existing-subscribers-vs-grandfathering)
  - [7. Member limit enforcement](#7-member-limit-enforcement)
  - [8. Known limitations](#8-known-limitations)
  - [9. Testing](#9-testing)
  - [10. Adapting this for a single-user app](#10-adapting-this-for-a-single-user-app)

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

| Plan | Price | Member limit | Custom domain |
|---|---|---|---|
| Free | $0 / £0 | 1 | No |
| Starter | $9.99/mo or £9.99/mo | 5 | No |
| Growth | $49.99/mo or £29.99/mo | 20 | Yes (one per org) |

Plans control `member_limit` and the Growth-only `custom_domain` flag (see
[Member limit enforcement](#7-member-limit-enforcement) and
[`docs/CUSTOM_DOMAINS.md`](CUSTOM_DOMAINS.md)). To add another plan-gated capability,
extend the `Plan` `Data.define` in `app/models/billing/plans.rb` with more fields and
read them wherever `Organization#current_plan` is already consulted.

**Free is a local-only phantom plan** - there is no Stripe Product/Price for it, and no
`Pay::Subscription` row is ever created for an org on Free. `Organization#current_plan` returns
`Billing::Plans::FREE` simply when there's no active subscription. This means a brand-new org
never touches the Stripe API until its owner clicks "Upgrade."

**Displayed price vs. charged price stay in sync automatically** - `Plan#prices` in
`app/models/billing/plans.rb` dynamically fetches the true, live amount from Stripe
(`Stripe::Price.retrieve`) and caches it for 12 hours. This ensures the UI always matches
exactly what Stripe charges. `fallback_cents` is defined in the model purely as a safety net
for automated tests or if the Stripe API is temporarily unreachable.

### Multi-currency

Each plan holds a *separate* `Price` (cents + Stripe price id) per entry in
`Billing::Plans::SUPPORTED_CURRENCIES` (currently `usd` and `gbp`) - a Stripe Price is fixed to
one currency, so "switching currency" always means picking a different Price object, never
converting an amount. There is no live exchange-rate conversion here.

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
  fail at Stripe anyway.

## 3. Stripe dashboard setup

Create the two paid Products, each with **two Prices - one per currency** (do this once per
Stripe account, in both test mode and live mode):

1. [dashboard.stripe.com/test/products](https://dashboard.stripe.com/test/products) → **+ Add
   product**. Create "Starter" with a recurring price of $9.99/month, **then add a second price**
   on the same product for £9.99/month (GBP). Repeat for "Growth" at $29.99/month and £29.99/month.
2. Copy each Price's id (starts with `price_...`, **not** the Product id) into
   `stripe.price_ids.starter.usd` / `.gbp` and `stripe.price_ids.growth.usd` / `.gbp` in credentials.
3. [dashboard.stripe.com/test/webhooks](https://dashboard.stripe.com/test/webhooks) → **+ Add
   endpoint**, URL `https://yourdomain.com/pay/webhooks/stripe` (Pay auto-mounts this route -
   there is no controller to write). Subscribe to the full set of events Pay's built-in handlers consume.

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

`private_key` and `signing_secret` are read automatically by the `pay` gem. `public_key` IS read
directly by this app for Stripe Elements. `price_ids` is this app's own addition, read by
`Billing::Plans`.

## 5. How it works

- **`Organization` is the Pay billable** (`app/models/organization.rb`):
  `pay_customer default_payment_processor: :stripe`.
- **Adding/updating a card**: the "Update payment method" button opens a `<dialog>` whose
  Stimulus controller fetches a SetupIntent client secret, mounts a Stripe Elements Payment Element,
  and calls `stripe.confirmSetup()`.
- **Removing a card** (`DELETE /billing/payment_method`): calls Pay's `PaymentMethod#detach`
  and destroys the local row. **Blocked while actively subscribed to a paid plan**, *unless* the
  subscription is already canceled and in its grace period. This ensures an org can't strand an
  active subscription with nothing to charge at renewal.
- **Subscribing / upgrading / downgrading** (Available via the "Change plan" modal):
  - **First subscribe from Free**: `payment_processor.subscribe` - charged today, unless eligible for a trial.
  - **Upgrade (more expensive plan)**: applied immediately via `subscription.swap`, prorated difference invoiced today.
  - **Downgrade (cheaper plan)**: takes effect **at the end of the current period**, implemented with a Stripe Subscription Schedule.
- **Canceling**: always cancels **at period end** (`cancel_at_period_end: true`).
- **Resuming**: while a cancelled subscription is in its grace period, a **Resume subscription** button is available.
- **Free trials**: the **first** paid subscription an org ever starts gets a 14-day free trial if it's the Starter plan.

### Managing billing from the Stripe Dashboard

- **Refunds: safe.**
- **Per-customer discounts: safe - use Coupons/promotion codes**.
- **Changing an individual subscription to a one-off custom Price: DON'T.** The app maps
  `processor_plan` (the Stripe price id) back to `Billing::Plans`. An unknown price id falls back to **Free**.

## 6. Price increases: migrating existing subscribers vs. grandfathering

Raising a plan's price (e.g. Starter $9.99 → $15.00) requires pointing `credentials.stripe.price_ids`
to a new Stripe Price ID. **Crucially, you must add the old Stripe Price ID to the `legacy_price_ids` array**
in `app/models/billing/plans.rb` so the app still recognizes existing subscribers as being on a paid plan.

Once registered, existing users are permanently grandfathered by default. Two admin tools handle moving them:

- **Migrating existing subscribers to the new price** (`/admin/price_migrations/new`):
  Select the plan and paste the old Stripe price id to preview which organizations are on that price.
  Confirming enqueues `Billing::MigratePriceJob`, moving each org to the new price via a Stripe Subscription Schedule.
  The new price takes effect seamlessly at the end of their current billing cycle.
- **Grandfathering**: Administrators can manually select users to permanently exclude from bulk
  migrations, keeping their rate locked in forever. Grandfathered users see a "Legacy Pricing"
  success banner on their billing dashboard.
- **The customer sees it coming**: While a price migration is pending, the billing page shows
  "Heads up - your price is changing to $X on \<date\>". Advance notice to customers via email is still your responsibility.

## 7. Member limit enforcement

Every plan caps organization size. **Both accepted memberships and outstanding (unrevoked,
unexpired) invitations count toward the limit**.

The limit is hard-blocked at `Org::InvitationsController#create` and `OrganizationInvitation#accept!`.
Downgrades/cancellations are never intercepted mid-cycle. Instead, `Billing::ReconcileOrganizationJob`
runs after every webhook and flags if an org is over its limit, showing a warning banner on `/billing`.

## 8. Known limitations

- **Accept-time race**: Two people accepting the same invitation at the exact same instant could bypass the check.
- **Wasted seats**: An unaccepted invitation reserves a seat until it expires (7 days).
- **One differentiator only**: Plans differ solely by member count.
- **3D Secure / SCA is handled minimally**: The embedded card form catches required off-page auth, but lacks a full guided retry flow.
- **Only one saved card at a time**: Adding a new card replaces the previous default.

## 9. Testing

Tests use Minitest and `Pay::FakeProcessor` (no real Stripe API calls):
- **Model/limit logic**: Wraps tests in `with_active_subscription(organization, plan)`.
- **SetupIntent/payment method sync**: Stubs the Stripe SDK boundary directly (`Stripe::Customer.stub`).
- **Webhooks**: Tested locally via `Billing::SubscriptionSyncHandler` rather than a full HTTP round-trip.

## 10. Adapting this for a single-user app

To turn this into a single-user variant:
- **Hide, don't remove**, the multi-tenant UI: the `namespace :org` routes/controllers/views.
- Remove "Organization Settings" / member list / invite form from the nav and settings pages.
- Leave `Role`/`Membership`/`Permission` models alone. `Organization` remains the billing anchor.
- Find a new differentiator: The default plans are differentiated by seat count, which is meaningless for a single-user app. Use usage limits or feature flags instead.