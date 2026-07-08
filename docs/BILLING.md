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

Upgrading happens entirely on Stripe's hosted pages via **Stripe Checkout**. Payment methods and
invoices are managed through the **Stripe Billing Portal** (`Billing::PortalSessionsController`),
plus two in-app actions on `/billing` that call the `pay` gem directly without leaving the app:
canceling the subscription (graceful, effective at the end of the current billing period, with a
"resume" undo while it's on its grace period) and removing the payment method on file. The app
never collects card details directly.

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

`public_key`, `private_key`, and `signing_secret` are read automatically by the `pay` gem
(`Pay::Stripe.public_key` / `.private_key` / `.signing_secret`) - no app code touches them
directly. `price_ids` is this app's own addition, read by `Billing::Plans::STARTER` /
`Billing::Plans::GROWTH`.

## 5. How it works

- **`Organization` is the Pay billable** (`app/models/organization.rb`):
  `pay_customer default_payment_processor: :stripe`. `Current.organization.payment_processor`
  lazily creates a local `Pay::Customer` row on first access, and lazily creates the real Stripe
  Customer (one API call) the first time `checkout` or `billing_portal` is called - never on a
  plain page view.
- **Checkout** (`app/controllers/billing/checkouts_controller.rb`, `POST /billing/checkouts`):
  looks up the requested plan in `Billing::Plans`, calls
  `organization.payment_processor.checkout(mode: "subscription", line_items: price_id, ...)`,
  and redirects to the returned Stripe-hosted session URL.
- **Billing Portal** (`app/controllers/billing/portal_sessions_controller.rb`,
  `POST /billing/portal_session`): redirects the owner to Stripe's hosted portal for managing
  payment methods and invoices.
- **Cancel / resume subscription** (`app/controllers/billing/subscriptions_controller.rb`,
  `DELETE /billing/subscription` / `POST /billing/subscription/resume`): calls
  `organization.payment_processor.subscription.cancel` (Pay's graceful cancel -
  `cancel_at_period_end: true`) or `.resume` directly against Stripe, no portal redirect. The
  subsequent `customer.subscription.updated`/`deleted` webhook still drives
  `Billing::ReconcileOrganizationJob` as usual (see below) - these actions don't bypass that path,
  they just also update `ends_at` locally so the UI reflects the grace period immediately.
- **Remove payment method** (`app/controllers/billing/payment_methods_controller.rb`,
  `DELETE /billing/payment_method`): detaches the default `Pay::PaymentMethod` from Stripe
  (`Pay::Stripe::PaymentMethod#detach`) and destroys the local row.
- **Webhooks**: Pay auto-mounts `POST /pay/webhooks/stripe` and verifies the signature itself.
  `config/initializers/pay.rb` subscribes `Billing::SubscriptionSyncHandler` to
  `customer.subscription.created/updated/deleted`, which enqueues
  `Billing::ReconcileOrganizationJob` to recompute the org's over-limit flag and write an
  `AuditLog` entry (`subscription_created`/`subscription_updated`/`subscription_cancelled`).
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

**Downgrades/cancellations never remove members automatically**, whether triggered from the
in-app cancel button or Stripe's Billing Portal. `Billing::ReconcileOrganizationJob` runs after
every subscription webhook and sets `organizations.over_member_limit_at` if the org is now over
its (possibly lower) limit. This only powers a banner on `/billing` and continues to block new
invites/accepts via the same guard above, until an owner either upgrades again or removes members
by hand.

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

## 8. Testing

Tests use Minitest (this app has no RSpec/FactoryBot). No real Stripe API calls are made:

- **Model/limit logic** uses Pay's built-in `Pay::FakeProcessor`, which creates real
  `Pay::Subscription` rows with no network calls. `test/test_helper.rb` exposes
  `with_active_subscription(organization, plan)`, which grants a fake active subscription *and*
  stubs `Billing::Plans.for_stripe_price` (since Pay's price-id resolution needs a real Stripe
  price id, which test credentials don't have) - wrap any assertion that depends on the org's
  plan/seat limit in this block. See `test/models/organization_test.rb` and
  `test/integration/billing_limits_test.rb`.
- **Checkout/Billing Portal** aren't modeled by the fake processor (they're inherently
  real-Stripe-API concerns), so those tests stub the Stripe SDK boundary directly
  (`Stripe::Customer.stub(:create, ...)`, `Stripe::Checkout::Session.stub(:create, ...)`,
  `Stripe::BillingPortal::Session.stub(:create, ...)`) rather than pulling in VCR/WebMock for a
  couple of narrow assertions. This requires the `minitest-mock` gem (minitest 6 split
  `Object#stub` out of the core gem - see the `Gemfile`'s `:test` group).
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
