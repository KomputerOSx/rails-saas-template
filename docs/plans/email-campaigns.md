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
- [7. Email preferences & unsubscribe](#7-email-preferences--unsubscribe)
- [8. Known limitations (MVP)](#8-known-limitations-mvp)
- [9. Roadmap (not built yet)](#9-roadmap-not-built-yet)

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
| `email_campaigns` | `subject`, `body_html` (sanitized), `status` (`draft`/`sending`/`sent`), `category` (`marketing`/`product_updates`/`important` — see §7), `max_width`, `created_by`, `sent_at` |
| `email_campaign_recipients` | Per-recipient delivery state: `sent_at`, `failed_at`, `skipped_at` (recipient had opted out of this campaign's category — see §7), `error_message` |
| `users.email_preferences` | Not a separate table — a `json` column on `users`, keyed by category string. See §7. |

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
2. `show` — a review screen: subject, rendered body preview, and (once sending has started) summary
   stat cards (total/sent/failed/pending). A "View all recipients" link goes to a separate
   `recipients` page with the full per-recipient table (email, status badge, error message) — kept
   off the main show page so it doesn't dominate the screen for large campaigns.
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

**Images are sent as inline (CID) attachments, not fetched URLs.** `body_html` stores
`<img src="https://.../rails/active_storage/blobs/redirect/...">` (see §6), but a static URL means
the recipient's mail client has to fetch it over the public internet when the email is opened —
which fails outright whenever the app isn't reachable from wherever the recipient is (not just
`localhost`; any non-public deployment, VPN-gated staging host, etc.). `EmailCampaignMailer`
sidesteps this entirely using `ActionMailer`'s built-in `attachments.inline[...]` (from the `mail`
gem, already a core dependency — no new gem needed):

1. `EmailCampaign#referenced_image_blobs_by_signed_id` scans `body_html` for
   `.../blobs/redirect/:signed_id/...` URLs and resolves each captured `signed_id` back to its
   `ActiveStorage::Blob` via `ActiveStorage::Blob.find_signed` — only the blobs this campaign's
   body actually references, not every image ever uploaded via the unattached-blob upload flow
   (see §6). Keyed by signed_id (rather than by blob) because Rails' signed IDs can be
   authenticated-encrypted, i.e. non-deterministic across calls — recomputing `blob.signed_id`
   fresh in the mailer would not reliably match the exact string embedded in `body_html`.
2. `EmailCampaignMailer#campaign` loops that hash, calling `attachments.inline[...] = blob.download`
   for each (name-spaced with the blob id to avoid two different blobs with the same original
   filename clobbering one attachment slot), and records each resulting `cid:...` reference keyed
   by the same signed_id.
3. The view (`campaign.html.erb`) calls `EmailCampaign#body_html_with_cid_images`, which does the
   `src="https://.../blobs/redirect/:signed_id/..."` → `src="cid:..."` swap immediately before
   rendering — the same regex, applied in reverse.

The image travels inside the email's own `multipart/related` MIME payload; the recipient's client
renders it from the message it already has, no fetch, no dependency on this app being deployed or
reachable at send time (`localhost` is genuinely fine now). The admin-facing `show.html.erb` preview
is unaffected by any of this — it keeps rendering `body_html`'s real HTTP URL as-is, since `cid:`
only resolves inside an actual MIME email, not a browser tab.

**Trade-off:** the image bytes are sent with *every* recipient's copy of the email (not served once
and cached), so a large image on a large campaign multiplies SMTP payload size — a 500KB image ×
1,000 recipients ≈ 500MB total through the SMTP relay for that one send. Reasonable for this app's
current scale (internal broadcast tool, not a marketing list); revisit if campaigns start recurring
at real marketing-list scale.

There's a second, sharper version of this same trade-off: SMTP relays (Azure Communication
Services included) cap the size of a **single** message, independent of recipient count - Azure's
limit is 10 MB per message, and base64 (how MIME encodes binary attachments) inflates raw bytes by
~33%, so the *referenced images' combined raw size*, not their sent size, is what has to stay under
budget. This was hit in practice (`501 5.6.0 Email payload must be less than 10 MB`), and because
`SendEmailCampaignJob` rescues per-recipient and always flips the campaign to `sent` once every
recipient's been attempted (see below), the failure mode was silent from the UI's perspective - the
campaign showed as sent while every single recipient had actually failed. Two guards now exist:
`Admin::EmailCampaignImagesController::MAX_FILE_SIZE` caps a single upload at 5 MB, and
`EmailCampaign#images_too_large_to_send?` (checked in `Admin::EmailCampaignsController#deliver`,
budget `EmailCampaign::MAX_TOTAL_INLINE_IMAGE_BYTES` = 6 MB raw) blocks the send outright with a
clear flash instead of enqueueing a batch that's guaranteed to fail for every recipient.

## 6. Editor

The rich text editor is [TipTap](https://tiptap.dev) (ProseMirror-based), chosen over
EditorJS because it outputs real HTML directly — what an email body needs — rather than
block-structured JSON that would need an extra render step, and EditorJS's block renderer isn't
built for email-safe HTML in the first place.

This app has no Node build step (`importmap-rails`; JS is pinned via CDN ESM URLs — see
`config/importmap.rb`). TipTap is pinned the same way as `tom-select`/`embla-carousel`/`motion`:
`@tiptap/core`, `@tiptap/starter-kit`, `@tiptap/extension-underline`, `@tiptap/extension-link`,
`@tiptap/extension-text-style`, `@tiptap/extension-color`, and `@tiptap/extension-image`, all via
`esm.sh`. A Stimulus controller (`app/javascript/controllers/rich_text_editor_controller.js`)
mounts the editor and mirrors its HTML into a hidden form field on every update, the same
"Stimulus writes a plain form field, the form POSTs normally" convention used everywhere else in
this app (no fetch/JSON for the body itself).

`StarterKit` is configured with `codeBlock`, `code`, `horizontalRule`, and `strike` disabled so
the editor can't produce markup outside what `EmailCampaign`'s server-side sanitizer allow-lists
(`p br strong em u a ul ol li h1 h2 h3 blockquote span img`, attributes `href style src alt width`).
Sanitization happens once, in a `before_save` callback — the mailer view renders the stored
`body_html` with `raw` on the assumption it was already cleaned at write time. Opening up `style`
(for text color and CTA buttons) and `img` widened the attack surface slightly; Rails' Loofah-backed
sanitizer scrubs dangerous CSS (`expression()`, `javascript:`, `behavior`, etc.) from `style` values
and strips non-allow-listed `img` attributes like `onerror` — verified with `rails runner` against
both a benign CTA-button snippet (preserved byte-for-byte) and adversarial input (stripped) before
shipping.

**Text color** uses `@tiptap/extension-color` + `@tiptap/extension-text-style` with a native
`<input type="color">` in the toolbar (no custom swatch picker — deliberately minimal) plus a
"Clear color" button, since a native color input has no way to represent "unset."

**Images** upload through a small dedicated endpoint, `POST /admin/email_campaign_images`
(`Admin::EmailCampaignImagesController`, gated by the same `system.email_campaigns.manage`
permission as everything else here), which wraps the uploaded file in an **unattached**
`ActiveStorage::Blob` (`ActiveStorage::Blob.create_and_upload!`, not associated with any model) and
returns its URL. Unattached rather than `has_many_attached :images` on `EmailCampaign` because the
editor is used on `new`, before a campaign record exists — attaching would force a premature save.
Tradeoff: uploaded-but-unused images are never cleaned up (no association, no cascade) — a future
periodic purge job is a roadmap item, not built.

The returned URL is built from `Rails.application.config.action_mailer.default_url_options` — the
same host every other mailer link in this app already uses — **not** `request.base_url`. This
matters: the admin composing a campaign might be reaching the app via an internal IP, VPN host, or
`localhost`, none of which mean anything to an external email recipient's mail client. Also note
`config.action_mailer.default_url_options` must actually be set to your real domain in
`config/environments/production.rb` — Rails ships this as the placeholder `"example.com"`, which
silently breaks *every* mailer link app-wide (password resets, invitations, confirmations too, not
just campaign images) until it's changed.

This URL is only ever used at compose/preview time (the editor inserts it, `show.html.erb`'s
preview renders it). At *send* time it's resolved back to an `ActiveStorage::Blob` and swapped for
an inline attachment — see §5 — so the sent email's rendering no longer depends on this host being
reachable by the recipient at all.

**Why not just fix the host and leave it a fetched URL?** Because "the recipient's mail client can
reach this URL" is a fact about *deployment*, not about anything a gem or code change here controls.
Testing against `localhost:3000` will never render externally no matter how correct the URL looks —
there's no way to make a laptop's `localhost` reachable from an external mail server. Several earlier
fixes to this feature (correcting the host, restricting to web-safe formats) were still hardening
that fundamentally-external-fetch approach; §5 replaces it with inline (CID) attachments, which
don't have this problem by construction.

**Image sizing** extends `Image` with a `width` attribute (`ResizableImage` in the controller) set
via toolbar presets (S/M/L/Reset, 200/400/600px) applied to whichever image node is currently
selected. This uses the legacy HTML `width` attribute rather than a CSS `width`/`max-width` style —
deliberately, since email clients (notably Outlook desktop, which renders via Word's engine) often
ignore CSS sizing on `<img>` but reliably respect the HTML attribute. No drag-handle resizing (that
would need a custom ProseMirror NodeView) — preset sizes only, matching this feature's consistently
minimal toolbar approach elsewhere (native color input over a swatch picker, etc.).

**Selected image indicator**: ProseMirror automatically toggles a `ProseMirror-selectednode` class
onto a clicked image's DOM element (built-in NodeSelection behavior, no JS needed) — styled with an
outline ring so it's clear which image the size buttons will act on.

**CTA buttons** are really just an `<a>` with a fixed inline style (real `<button>` elements don't
render usefully in email). TipTap's `Link` mark only declares `href`/`target`/`rel`/`class` by
default, so a bare `style` attribute would be silently dropped on every `getHTML()` serialization —
the controller extends `Link` once (`CampaignLink`) to also declare a pass-through `style`
attribute. Plain links created via the existing "Link" toolbar button never set `style`, so they're
unaffected. The "+ Button" toolbar action opens a dialog (`data-controller="modal"`, same pattern
as `org/settings/_name_editor.html.erb`) with label/URL inputs and a color `<select>`
(green/blue/red/purple/black, applied at insertion time only — doesn't retroactively recolor a
button already in the document) — replacing an earlier version that used `window.prompt()`, which
doesn't fit this app's UI and offered no way to pick a color without cramming a second control into
the toolbar itself. Colors are plain hex, not this app's actual `--color-primary` etc.: email
clients don't reliably support `oklch()`/CSS custom properties.

**Text and image alignment** are separate controls because a per-node CSS `text-align` only affects
inline content — TipTap's `Image` node is block-level, so aligning an image needs margin, not
`text-align`, to actually move it. Left/Center/Right for paragraphs and headings uses the official
`@tiptap/extension-text-align` (pinned via importmap like every other TipTap piece here, `types:
['heading', 'paragraph']`), which renders a plain `style="text-align: ..."` — already inside
`ALLOWED_ATTRIBUTES`, no sanitizer change needed. Left/Center/Right for images is a custom `align`
attribute on `ResizableImage` (`app/javascript/controllers/rich_text_editor_controller.js`) that
renders `display:block` plus `margin:0` / `margin:0 auto` / `margin-left:auto` respectively — the
same `margin:auto` technique used broadly in HTML email because it (unlike `float`) holds up in
Outlook desktop. Its `parseHTML` recognizes those same three style strings on load, so alignment
round-trips correctly when reopening a saved campaign for editing. The image-align buttons sit
inside the existing "Image" toolbar group, next to the S/M/L/Reset size buttons — same "applies to
whichever image node is currently selected" behavior.

**Links** use the same dialog pattern as "+ Button" (`data-controller="modal"`, a single URL field)
instead of `window.prompt()` — opening the dialog pre-fills the field with the current link's `href`
if the selection is already a link, so it doubles as an edit flow. "Unlink" stays a direct one-click
toolbar action outside the dialog, since removing a link needs no input.

**Email width** is a campaign-level (not per-node) control in the "Body" card header, distinct from
everything else in the toolbar: `EmailCampaign::MAX_WIDTHS` (narrow/standard/wide — 480/600/720px)
picks the content column's width, persisted as a plain `max_width` integer column, validated against
`EmailCampaign::MAX_WIDTHS.values`, rather than living inside `body_html` itself, since it applies to
the email as a whole. Picking a preset live-resizes the compose canvas (`rich-text-editor` Stimulus
controller's `applyEmailWidth`) so composing previews the actual layout, and the same value drives
both the mailer's email-safe centered-table wrapper (`campaign.html.erb` — HTML `width` attribute +
CSS `max-width` for Outlook/mobile) and the admin `show.html.erb` preview, so both surfaces agree.

Colors (header/footer background, body background, header/footer text) were originally a second pair
of per-campaign `bg_color`/`fg_color` columns with their own color pickers, but were removed in
favor of hardcoded constants — `EmailCampaign::HEADER_FOOTER_BG`, `HEADER_FOOTER_TEXT`, `BODY_BG`
(`app/models/email_campaign.rb`) — once the layout below made per-campaign color choice pointless (a
fixed brand look, not a customizable one). No migration-worthy state left behind: the columns were
dropped, not just hidden from the UI.

**Header, body, and footer are three full-width bands, not a centered rounded card.** An earlier
version wrapped everything in one canvas-color-behind-a-rounded-card layout (`bg_color` on the outer
canvas, `fg_color` + `border-radius: 12px` on an inset card); that's been replaced with a flatter,
edge-to-edge design: header and footer both render at `HEADER_FOOTER_BG` (a darker brand green) with
white text, body renders at the lighter `BODY_BG` tint, and none of the three rows carry a
`border-radius` — separation between sections comes purely from the color contrast between them, not
from card-shaped insets. `campaign.html.erb`'s outer table (full page width, `#ffffff`, purely for
horizontal centering) is unchanged; only the inner `max_width` column's per-row backgrounds changed.

**Header and footer are static ERB, not admin-editable** — a deliberate departure from everything
else on this page, which is either TipTap-authored (`body_html`) or a per-campaign field (width).
TipTap is block-based rich text; it has no good way to express a header/footer's more deliberate
fixed layout (a full-width band, a multi-line footer with several link rows), and there's still no
logo file anywhere in the app to make an admin-editable version worth the extra settings-model/UI
surface. `app/views/email_campaign_mailer/_header.html.erb` and `_footer.html.erb` are plain `<tr>`
partials rendered inside the same outer `max_width` table as the body (`campaign.html.erb`). The same
two partials are rendered again in `show.html.erb`'s preview (table-based, matching the sent email's
actual markup) so preview and send agree. Editing the copy or layout means editing these two files
and deploying — there is no admin screen for it, by design.

The footer is a proper multi-row section, not a single disclaimer line: a "Contact us" button
(`mailto:hello@windtunnel.example` — the `.example` TLD is IANA-reserved specifically so a
placeholder address like this can never resolve to a real inbox), a quick-links row (Help Center /
Privacy Policy / Terms of Service, all `href="#"` placeholders), a social-links row (Twitter /
LinkedIn / Instagram, same placeholder `#` hrefs — plain text links, not icons, since this app has no
vendored social-icon SVG set and inline SVG support in email clients is unreliable anyway), a fake
company name/address block, and the existing "you're receiving this because..." + conditional
"Manage your email preferences" line (unchanged logic - see §7; still governed by campaign `category`,
still absent entirely for `important` campaigns). **All placeholder content (address, fake email,
`#` hrefs) needs replacing with real values before this goes to real recipients** - flagged inline in
the partial's own ERB comment too, not just here.

**Verification note:** this app's dev sandbox proxy blocks `esm.sh`/`cdn.jsdelivr.net` outbound
(org egress policy — not a bug), so the CDN module resolution could not be live-verified from
inside that environment. Verify in a real browser on first run: open `/admin/email_campaigns/new`,
confirm the toolbar works and the browser console shows no ProseMirror "mismatched transaction" /
duplicate-plugin errors (the classic symptom of an ESM CDN failing to dedupe a shared peer
dependency across two separately-pinned packages). If it doesn't hold up, fall back to vendoring a
single pre-bundled ESM file into `vendor/javascript/` (built once via a local `esbuild` step) and
pin that locally instead, same as `turbo.min.js`/`stimulus.min.js`.

## 7. Email preferences & unsubscribe

Every campaign has a `category` (`EmailCampaign` enum: `marketing` / `product_updates` /
`important`, default `marketing`). `EmailCampaign::OPTIONAL_CATEGORIES` (`categories.keys -
["important"]`) is the single list every other piece of this feature iterates over — the admin
compose form's type selector, the user-facing preference checkboxes, the send-time skip check — so
adding a fourth category later is one enum entry, nothing else to touch. `important` is deliberately
excluded everywhere: always delivered, never shown as something a user can opt out of, no
`List-Unsubscribe` header, no link in the footer.

**Storage**: `users.email_preferences` is a `json` column, a hash keyed by category string.
Semantics are deliberately "absent key = subscribed" (`false` = opted out, no other values used) —
`User#subscribed_to_email_category?`/`#unsubscribe_from_email_category!`/
`#resubscribe_to_email_category!` (`app/models/user.rb`) encode this. This means a newly-added
category needs **zero backfill**: every existing user is implicitly subscribed to a category they've
never expressed an opinion on, since their hash simply has no key for it yet.

**Send-time enforcement**: `SendEmailCampaignJob` checks `!campaign.important? &&
!recipient.user.subscribed_to_email_category?(campaign.category)` before attempting delivery: if
true, `recipient.mark_skipped!` and move on, no mailer call at all. `skipped_at` is a third terminal
state on `EmailCampaignRecipient`, distinct from `sent_at`/`failed_at` — an opt-out isn't a delivery
failure and shouldn't count against failure-rate numbers. `recipient_counts` and the `show`/
`recipients` admin views surface it separately ("Skipped (unsubscribed)").

**The unsubscribe link**: `User#signed_id(purpose: :email_unsubscribe, expires_in: nil)` — no new
token table. This is a deliberate deviation from how this app's other emailed-link flows work
(`PasswordResetToken`, `OrganizationInvitation` both use a dedicated digest table with `expires_at`
and single-use semantics). An unsubscribe link should keep working indefinitely (expiring it would be
actively bad), and flipping a preference is idempotent/replayable in a way redeeming a password
reset isn't — so `signed_id`'s built-in non-expiring, stateless verification is the better fit, not
an inferior shortcut. Trade-off, stated plainly: because the token isn't stored/revocable, a leaked
link (forwarded email, shared computer, a corporate link-scanning proxy) lets whoever has it flip
that user's category preferences indefinitely. Accepted because the blast radius is "which marketing
emails you get," not account access — and `EmailPreferencesController`'s pages show nothing else
about the account (no name, no other settings) to keep that blast radius narrow.

**`EmailPreferencesController`** (`app/controllers/email_preferences_controller.rb`, public,
`allow_unauthenticated_access`, mirrors the existing `get "invitations/:token"` convention):
- `GET /email_preferences/:token` — never mutates. Corporate email security gateways pre-fetch/scan
  links in incoming mail; a mutating GET would cause accidental mass-unsubscribes across every
  recipient of every campaign the moment it's sent. Renders checkboxes for each
  `OPTIONAL_CATEGORIES`, current state pre-filled, the category from `?category=` (whitelisted
  against `OPTIONAL_CATEGORIES`, never trusted blindly) called out as the one that was clicked.
- `PATCH /email_preferences/:token` — that page's own form submission. Same "unauthenticated but
  same-request CSRF token" pattern `PasswordResetsController#update` already uses — the token
  embedded in the page it just rendered is valid, so this needs no special CSRF handling.
- `POST /email_preferences/:token/one_click` — the [RFC 8058](https://www.rfc-editor.org/rfc/rfc8058)
  `List-Unsubscribe-Post` target: what Gmail/Outlook/Yahoo's native "Unsubscribe" button next to the
  sender name actually calls, server-to-server, with **no CSRF token or cookies at all**. Without
  `skip_forgery_protection only: :one_click` on this controller (this app's `ApplicationController`
  otherwise has zero CSRF carve-outs anywhere), every native-button unsubscribe would 422. Safe to
  exempt because RFC 8058 defines this exact endpoint to be a no-confirmation, side-effect-bearing
  POST by design — unlike the bare-GET case above, this one *is* meant to mutate on a single hit.
- `EmailCampaignMailer#campaign` sets `List-Unsubscribe`/`List-Unsubscribe-Post` headers pointing at
  the one-click endpoint, and passes the (non-`important`) preference-center URL into the footer
  partial as an explicit `unsubscribe_url:` local — not a shared instance variable — so the
  dependency between what the mailer computes and what the footer renders is visible at the render
  call site, not implicit shared state between two otherwise-unrelated controllers (the mailer and
  `Admin::EmailCampaignsController#show`'s preview, which always passes `unsubscribe_url: nil`).

**Profile page**: logged-in users manage the same preferences without a token, via a "Notifications"
card on `/profile` (`ProfileController#update_email_preferences`) — same checkbox-array semantics as
the public preference center, operating on `current_user` directly.

**Not built**: audit-logging unsubscribe events (`AuditLog#event_type`'s enum is admin-action shaped
— every existing use is an admin acting on a resource, not a user's own self-service change; didn't
force the fit), a `mailto:` fallback in `List-Unsubscribe` (this app has no real unsubscribe mailbox
configured — a fake one would be worse for deliverability than a single working URL), and open/click
analytics (see §9 Roadmap — separate, larger, deliberately deferred).

## 8. Known limitations (MVP)

- **No scheduling** — `deliver` sends immediately; there is no "send at a future time."
- **Unsubscribe links don't expire or revoke** — see §7. A leaked preference-center link lets
  whoever has it flip that user's category preferences indefinitely; accepted because the blast
  radius is "which marketing emails you get," not account access.
- **No analytics** — no open/click tracking.
- **No orphaned-image cleanup** — uploaded images not embedded in any saved campaign (or embedded
  in a campaign that's later deleted) are never purged from storage.
- **No test-send-to-self** — the only way to see the final email is to send it for real, or read
  the rendered `show` page preview.
- **No recipient pagination** — the `recipients` detail page loads every recipient at once; fine
  at this scale, would need pagination for campaigns with very large audiences.
- **No CSS inlining** — `body_html` is rendered as-is inside the shared `mailer` layout, which has
  no inlining step. Fine for the simple tag set the sanitizer allows today (the editor's sanitizer
  only allows already-inline `style="..."` attributes — colors, CTA buttons — nothing relies on a
  `<style>` block or CSS classes surviving); would need `premailer-rails` (hooks into
  `ActionMailer` automatically, no per-mailer wiring) if the allowed markup ever grows to include
  class-based or `<style>`-block styling, since most mail clients strip `<style>` blocks entirely.
  A separate concern from image rendering — see §5 — not addressed by inlining images.
- **Inline images multiply SMTP payload size per send** — see §5. Embedding images as CID
  attachments means the image bytes travel with every recipient's copy rather than being served
  once and cached; a large image on a large campaign multiplies total payload sent through the
  relay accordingly. Reasonable at this app's current scale, worth revisiting only if campaigns
  start recurring at real marketing-list scale.

## 9. Roadmap (not built yet)

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
  `EmailCampaignRecipient`, prevents double-sends. Should check `User#subscribed_to_email_category?`
  before each send the same way `SendEmailCampaignJob` does now (see §7) - a sequence step needs a
  `category` too, not just a `subject`/`body_html`.
- Delivery is **not** request-triggered — a recurring Solid Queue task (following the existing
  pattern in `config/recurring.yml`) polls periodically for enrollments whose next step is due
  and sends it. This decouples send-time from enrollment-time, so a step's copy can still be
  edited after users are already enrolled but before their delay elapses.
- Additional trigger events (trial started, subscription cancelled, etc.) are just new enum
  values plus one call site each — no structural change needed once the first trigger exists.

### Scheduling one-off campaigns

Add a nullable `scheduled_at` to `email_campaigns`; a recurring job picks up drafts whose
`scheduled_at` has passed and calls the same `deliver!` path a manual click uses today.

### Analytics

Open tracking (1x1 pixel) and click tracking (redirect links through a signed short URL) would
each need their own table (`email_campaign_opens`, `email_campaign_clicks`) and a tracking
controller — meaningful additional surface area, deliberately deferred.

### Orphaned image cleanup

A periodic Solid Queue task (following the existing `config/recurring.yml` pattern) purging
unattached `ActiveStorage::Blob`s older than N days that were uploaded via
`Admin::EmailCampaignImagesController` but never ended up embedded in a saved campaign's
`body_html` (or whose campaign was later deleted).
