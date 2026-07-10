# Email campaigns

How outbound email campaigns work today, and the roadmap for automated/lifecycle email that is
explicitly **not** built yet.

## Contents

- [1. Overview](#1-overview)
- [2. Data model](#2-data-model)
- [3. RBAC](#3-rbac)
- [4. Composing and sending](#4-composing-and-sending)
- [5. Delivery mechanism](#5-delivery-mechanism)
- [6. Editor](#6-editor)
- [7. Known limitations (MVP)](#7-known-limitations-mvp)
- [8. Roadmap (not built yet)](#8-roadmap-not-built-yet)

---

## 1. Overview

`Admin::EmailCampaignsController` lets a `system_admin` compose a one-time email (subject + rich
text body) and send it immediately to a chosen set of platform `User`s — either everyone, or a
specific subset picked from a searchable list.

This is a **platform-wide admin tool**, not a per-organization marketing feature. It sends real
email via `ActionMailer`, unlike `Notification`/`Admin::NotificationsController`, which is
in-app-only. The two features share the same UX shape (compose → pick recipients → broadcast →
track per-recipient outcome) and `Admin::NotificationsController` is the direct structural
template `Admin::EmailCampaignsController` was built from.

## 2. Data model

```
EmailCampaign ──< EmailCampaignRecipient >── User
```

| Table | Purpose |
|-------|---------|
| `email_campaigns` | `subject`, `body_html` (sanitized), `status` (`draft`/`sending`/`sent`), `created_by`, `sent_at` |
| `email_campaign_recipients` | Per-recipient delivery state: `sent_at`, `failed_at`, `error_message` |

A campaign starts as `draft` (created, recipients snapshotted, nothing sent). `deliver` flips it
to `sending` and enqueues delivery; the job flips it to `sent` once every recipient has been
attempted. `sent` is terminal — a sent campaign cannot be edited, re-sent, or deleted.

## 3. RBAC

New permission: `system.email_campaigns.manage` — granted to `system_admin` only (not
`system_user`), same tier as `system.billing.manage`. Mass-emailing every platform user is
high-blast-radius enough to warrant the stricter role. See `docs/rbac.md` §3 for the full
permission catalog and §13 for how to add new permissions in general.

`SystemPolicy#manage_email_campaigns?` gates every `Admin::EmailCampaignsController` action, on
top of the coarse `Admin::BaseController` namespace gate (`SystemPolicy#manage?`) — the standard
two-tier pattern documented in `docs/rbac.md` §7.

## 4. Composing and sending

1. `new`/`create` — subject, rich text body, and recipients (`send_to_all` or specific
   `user_ids`, same picker UI as `Admin::NotificationsController#new`) are submitted together.
   `EmailCampaign.create_draft!` persists the campaign and one `EmailCampaignRecipient` row per
   target user, but sends nothing yet.
2. `show` — a review screen: subject, rendered body preview, recipient count, and (once sending
   has started) a live per-recipient status table.
3. `deliver` (explicit, confirmed action, `draft` only) — flips status to `sending` and enqueues
   the send. Splitting compose from send is deliberate: an in-app `Notification` can be withdrawn
   after the fact, but email cannot be recalled once delivered, so campaigns get an explicit
   review step first.

## 5. Delivery mechanism

One `SendEmailCampaignJob` (Solid Queue) is enqueued per campaign, not one job per recipient. It
loops over recipients and sends each with an individual `begin/rescue`, so one bad address can't
halt the batch — the same shape as `Billing::MigratePriceJob`, which loops organizations with a
per-organization rescue. This was chosen over `deliver_later` per recipient (N independent jobs
make the `draft → sending → sent` status transition awkward to track correctly) and over sending
synchronously in the controller (blocks the request for N SMTP round-trips, no recovery on
timeout).

## 6. Editor

The rich text editor is [TipTap](https://tiptap.dev) (ProseMirror-based), chosen over
EditorJS because it outputs real HTML directly — what an email body needs — rather than
block-structured JSON that would need an extra render step, and EditorJS's block renderer isn't
built for email-safe HTML in the first place.

This app has no Node build step (`importmap-rails`; JS is pinned via CDN ESM URLs — see
`config/importmap.rb`). TipTap is pinned the same way as `tom-select`/`embla-carousel`/`motion`:
`@tiptap/core`, `@tiptap/starter-kit`, and (since StarterKit does not bundle these two)
`@tiptap/extension-underline` and `@tiptap/extension-link`, all via `esm.sh`. A Stimulus
controller
(`app/javascript/controllers/rich_text_editor_controller.js`) mounts the editor and mirrors its
HTML into a hidden form field on every update, the same "Stimulus writes a plain form field, the
form POSTs normally" convention used everywhere else in this app (no fetch/JSON).

`StarterKit` is configured with `codeBlock`, `code`, `horizontalRule`, and `strike` disabled so
the editor can't produce markup outside what `EmailCampaign`'s server-side sanitizer allow-lists
(`p br strong em u a ul ol li h1 h2 h3 blockquote`, `href` only). Sanitization happens once, in a
`before_save` callback — the mailer view renders the stored `body_html` with `raw` on the
assumption it was already cleaned at write time.

**Verification note:** this app's dev sandbox proxy blocks `esm.sh`/`cdn.jsdelivr.net` outbound
(org egress policy — not a bug), so the CDN module resolution could not be live-verified from
inside that environment. Verify in a real browser on first run: open `/admin/email_campaigns/new`,
confirm the toolbar works and the browser console shows no ProseMirror "mismatched transaction" /
duplicate-plugin errors (the classic symptom of an ESM CDN failing to dedupe a shared peer
dependency across two separately-pinned packages). If it doesn't hold up, fall back to vendoring a
single pre-bundled ESM file into `vendor/javascript/` (built once via a local `esbuild` step) and
pin that locally instead, same as `turbo.min.js`/`stimulus.min.js`.

## 7. Known limitations (MVP)

- **No scheduling** — `deliver` sends immediately; there is no "send at a future time."
- **No unsubscribe/opt-out** — every targeted `User` receives the email; there is no per-user
  preference or suppression list. Acceptable for an internal/admin broadcast tool at this scale,
  but would need addressing before this is used for anything resembling marketing email at
  volume (see CAN-SPAM/opt-out roadmap item below).
- **No analytics** — no open/click tracking.
- **No image embedding** — the editor and sanitizer allow-list are both text/formatting only, no
  `<img>`. Adding images means Active Storage plus an upload UI in the editor toolbar.
- **No test-send-to-self** — the only way to see the final email is to send it for real, or read
  the rendered `show` page preview.
- **No CSS inlining** — `body_html` is rendered as-is inside the shared `mailer` layout, which has
  no inlining step. Fine for the simple tag set the sanitizer allows today; would need
  `premailer-rails` or similar if the allowed markup ever grows to include layout-heavy HTML.

## 8. Roadmap (not built yet)

Concepts sketched here to guide future work, not implemented:

### Automated lifecycle / drip sequences

A sequence of timed emails tied to a trigger event (e.g. `user_registered`), auto-enrolling new
users — the "welcome series" / onboarding drip pattern.

- `EmailSequence` (`name`, `trigger_event`, `active`) ──< `EmailSequenceStep` (`position`,
  `subject`, `body_html`, `delay_hours` since enrollment) — reuses the same TipTap editor and
  sanitizer as campaigns.
- `EmailSequenceEnrollment` (`user`, `sequence`, `enrolled_at`, `status`) created at the trigger
  point — e.g. a one-line call from `ConfirmationsController#create`, right where
  `Organization.create_personal_for!(user)` already runs today.
- `EmailSequenceDelivery` (per enrollment, per step) — same per-recipient tracking role as
  `EmailCampaignRecipient`, prevents double-sends.
- Delivery is **not** request-triggered — a recurring Solid Queue task (following the existing
  pattern in `config/recurring.yml`) polls periodically for enrollments whose next step is due
  and sends it. This decouples send-time from enrollment-time, so a step's copy can still be
  edited after users are already enrolled but before their delay elapses.
- Additional trigger events (trial started, subscription cancelled, etc.) are just new enum
  values plus one call site each — no structural change needed once the first trigger exists.

### Scheduling one-off campaigns

Add a nullable `scheduled_at` to `email_campaigns`; a recurring job picks up drafts whose
`scheduled_at` has passed and calls the same `deliver!` path a manual click uses today.

### Unsubscribe / opt-out

A `users.email_campaigns_opt_out` boolean (or a dedicated preferences table if per-category
opt-out is ever needed) plus a footer link in the mailer view, checked before each send in both
the one-off campaign job and the sequence delivery job.

### Analytics

Open tracking (1x1 pixel) and click tracking (redirect links through a signed short URL) would
each need their own table (`email_campaign_opens`, `email_campaign_clicks`) and a tracking
controller — meaningful additional surface area, deliberately deferred.

### Image embedding

Requires Active Storage integration in the TipTap toolbar (upload → attach → insert `<img>`) and
expanding the sanitizer allow-list to permit `img[src,alt]` — needs care since it also changes
what the editor's `StarterKit` config permits.
