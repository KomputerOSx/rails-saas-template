# Organization ownership lifecycle

How an organization gets its first owner, how it can gain or lose owners after that, and how
account deletion interacts with ownership. This is a deep dive into one corner of the broader
RBAC system documented in `docs/rbac.md` - read that first for the general permission model;
this doc covers the `owner` role specifically, end to end.

## Contents

- [1. Overview](#1-overview)
- [2. Data model](#2-data-model)
- [3. Invariants](#3-invariants)
- [4. Flow: organization creation](#4-flow-organization-creation)
- [5. Flow: promoting a member to co-owner](#5-flow-promoting-a-member-to-co-owner)
- [6. Flow: demoting an owner (self or peer-initiated)](#6-flow-demoting-an-owner-self-or-peer-initiated)
- [7. Flow: removing an owner / leaving](#7-flow-removing-an-owner--leaving)
- [8. Flow: account deletion](#8-flow-account-deletion)
- [9. Permissions](#9-permissions)
- [10. Audit events](#10-audit-events)
- [11. Emails](#11-emails)
- [12. UI reference](#12-ui-reference)
- [13. Testing](#13-testing)
- [14. Known limitations](#14-known-limitations)

---

## 1. Overview

Ownership is **not** a single `owner_id` column on `Organization` - it's a role
(`Role::APP_OWNER`) granted on a `Membership` (the user ↔ org join), exactly like `admin` and
`user`. That means an organization can have **multiple owners at once**, and the whole ownership
lifecycle is really just role grants/revokes on `MembershipRole`, guarded so an org can never end
up with zero owners and ownership can never be stripped from someone without their own
confirmation.

Four things changed hands to build this out:

1. **Promotion** - an owner can add a co-owner (`Org::MembersController#promote_to_owner`).
2. **Demotion** - any owner can demote themselves or a peer owner to admin
   (`Org::MembersController#demote_owner`), but the confirmation code always goes to the person
   being demoted.
3. **Removal lockdown** - owners can no longer be force-removed or leave directly; demotion is
   the only door out of the `owner` role.
4. **Account deletion guard** - a user can't delete their account if doing so would silently
   strip other people's org membership out from under them.

## 2. Data model

```
User ──< Membership >── Organization
Membership ──< MembershipRole >── Role (scope: app)
```

| Table | Relevant columns |
|-------|-------------------|
| `memberships` | `user_id`, `organization_id` (unique together - one membership per user per org) |
| `membership_roles` | `membership_id`, `role_id`, `granted_by_id` |
| `roles` | `scope: "app"`, `name: "owner"/"admin"/"user"`, `permanent` (`owner` is permanent - can't be renamed/deleted) |
| `users` | Three independent confirmation-code column pairs (digest + sent-at), one per sensitive action - see §11 |

No role has a numeric "level" column; the hierarchy (`owner` > `admin` > `user`) is expressed
entirely through which actions/permissions exist and who they're gated to, not a comparable
field. `Membership#has_role?(name, scope:)` and `Organization#email` (which reads the org's
Stripe customer email off *an* owner membership) are the two places code reasons about "the"
owner despite multiple being possible.

## 3. Invariants

These hold everywhere in the app, enforced at the model and controller layers described in the
sections below:

- **An org always has at least one owner.** `MembershipRole#prevent_removing_last_owner`
  (`app/models/membership_role.rb`) is a `before_destroy` callback that blocks destroying the
  last `owner` `MembershipRole` in an org - it throws `:abort`, so `Membership#revoke_role!`
  and `Membership#destroy` both return `false`/falsy instead of raising, and every caller checks
  that return value.
- **Ownership can only be added by an existing owner, and only with that owner's own
  confirmation.** `#promote_to_owner` requires the acting owner to type the target's email and
  enter a code emailed to *themselves*.
- **Ownership can only be removed with the target owner's own confirmation.** `#demote_owner`'s
  code always goes to the membership being demoted, whether they initiated it or a peer did.
- **Owners can never be force-removed from the org.** `destroy` (remove member) and `leave`
  (self-removal) both reject any membership currently holding the `owner` role outright, no
  matter how many owners exist. Demote first, then remove/leave normally.
- **Deleting your own account never silently kicks other people out of an org.** See §8.

## 4. Flow: organization creation

`Organization.create_personal_for!(user)` (`app/models/organization.rb`), called from
`ConfirmationsController#create` and `OmniauthCallbacksController` on first signup:

```ruby
organization = create!(name: name, slug: generate_unique_slug(base))
membership = organization.memberships.create!(user: user)

owner_role = Role.find_or_create_by!(scope: :app, name: Role::APP_OWNER) do |role|
  role.permanent = true
  role.description = "Organization owner - full control; cannot be removed while sole owner"
end
membership.grant_role!(owner_role)
```

Every user gets exactly one personal org at signup, with themselves as its sole owner. There's
no path to create an org with zero owners or more than one owner at creation time - additional
owners only ever come from `#promote_to_owner` afterward.

## 5. Flow: promoting a member to co-owner

`Org::MembersController#promote_to_owner` / `#send_promotion_code`. Requires
`app.members.promote_owner` (owner-only permission).

1. On the members table (`org/settings`), an owner opens a non-owner member's row → "Edit
   member" dialog → "Promote to owner" section
   (`app/views/org/members/_edit_dialog_content.html.erb`).
2. They click "Send code to my email" → `POST send_promotion_code_org_member_path` →
   `current_user.request_ownership_promotion_code!` generates a 6-digit code, stores its digest
   on the **acting owner's** `users` row, and emails it to the **acting owner** via
   `OwnershipPromotionMailer`.
3. They type the **target member's email** (not their own - this guards against promoting the
   wrong row by mistake) and the code, then submit → `PATCH promote_to_owner_org_member_path`.
4. `Org::MembersController#promote_to_owner` checks the typed email against
   `@membership.user.email`, verifies the code against `current_user.verify_ownership_promotion_code!`,
   then calls `@membership.grant_role!(owner_role, granted_by: current_user)`.
5. The target now holds the `owner` role **in addition to** whatever they had - this is purely
   additive. The original owner is untouched; the org now has two (or more) owners.

The confirmation code is sent to the **acting** owner because the risk being guarded against is
"someone else is driving my session" (matches the account-deletion confirmation pattern), not
"does the target consent" - the target isn't being asked to agree to anything, since gaining a
role is not something anyone needs to consent to.

## 6. Flow: demoting an owner (self or peer-initiated)

`Org::MembersController#demote_owner` / `#send_owner_demotion_code`. Requires
`app.members.demote_owner` (owner-only permission), and the target membership must currently
hold the `owner` role (`reject_non_owner_target`).

This is the mirror image of promotion, with one deliberate difference: **the confirmation code
always goes to the person being demoted, never to whoever clicked the button.**

1. Any owner opens an owner row in the members table. Their own row shows "Step down as owner";
   any other owner's row shows "Demote to admin"
   (`app/views/org/members/_demote_owner_dialog_content.html.erb`).
2. "Send code" → `POST send_owner_demotion_code_org_member_path` →
   `@membership.user.request_owner_demotion_code!` stores the digest on the **target's** `users`
   row and emails it to the **target** via `OwnerDemotionMailer` (`@self_initiated` in the mailer
   just changes the wording between "you requested to step down" vs. "`<initiator>` requested to
   demote you").
3. Whoever has that code (the target themselves, most likely) types the target's email and the
   code, then submits → `PATCH demote_owner_org_member_path`.
4. `Org::MembersController#demote_owner` checks the typed email against `@membership.user.email`,
   verifies the code against **`@membership.user.verify_owner_demotion_code!`** (the target, not
   `current_user`), then:
   ```ruby
   if @membership.revoke_role!(owner_role)
     @membership.grant_role!(admin_role, granted_by: current_user)
     # success
   else
     # MembershipRole#prevent_removing_last_owner blocked it - target is the sole owner
   end
   ```
5. On success the membership holds `admin` instead of `owner`. If the target was the org's only
   owner, `revoke_role!` returns `false` (the last-owner guard fired) and nothing changes.

Practical effect: a peer owner can *start* a demotion, but it silently goes nowhere unless the
target owner's own inbox produces the code - there's no way to strip someone's ownership without
their cooperation, short of also compromising their email.

## 7. Flow: removing an owner / leaving

Before this feature, `destroy` (remove member) and `leave` (self-removal) only had the
model-level last-owner guard - meaning a *non-sole* owner could be deleted outright by anyone
with `app.members.remove`, with no confirmation at all. That loophole is closed:

- **`Org::MembersController#destroy`** - `reject_owner_target` (a `before_action`) rejects the
  request before it ever reaches `@membership.destroy` if the target holds the `owner` role,
  regardless of how many owners the org has. Message: "Owners can't be removed directly. Demote
  them to admin first."
- **`Org::MembersController#leave`** - same check, inline at the top of the action, before the
  self-removal `destroy` call. Message: "Step down as owner before leaving the organization."

Once an owner has been demoted (§6), their membership is a normal `admin`, and `destroy`/`leave`
work exactly as they do for anyone else.

`reject_owner_target` also still covers the admin ↔ user `promote`/`demote` toggle actions
(unrelated to ownership - an owner target never makes sense there either).

## 8. Flow: account deletion

`ProfileController#destroy`. Account deletion already required typed-email + emailed-code
confirmation (`AccountDeletionMailer`, `User#request_account_deletion_code!` /
`#verify_account_deletion_code!`) before this feature; what changed is what happens when the
deleting user owns organizations.

A pre-flight check runs **before** the typed-confirmation/code prompt (so a doomed request fails
fast, without making the user go fetch a code first):

```ruby
def sole_owner_with_other_members?(org)
  is_sole_owner = org.membership_roles.joins(:role, :membership)
    .where(roles: { scope: "app", name: Role::APP_OWNER })
    .where.not(memberships: { user_id: current_user.id })
    .none?

  is_sole_owner && org.memberships.where.not(user_id: current_user.id).exists?
end
```

| Situation | Result |
|-----------|--------|
| Sole owner of an org, org has other members (any role) | **Blocked.** Redirected to `/profile` with an error naming the org(s); no destructive action taken. Must promote a co-owner (§5) or remove the other members first. |
| Sole owner of an org, org has no other members | Allowed. Deleting the account also destroys the org (nothing else in it to preserve). |
| Not the sole owner (a co-owner exists) | Allowed. Only this user's own membership is removed; the org and its other members are untouched. |

The destroy transaction itself is unchanged from before this feature - for each org where the
user is the sole owner, it bypasses `MembershipRole#prevent_removing_last_owner` with a raw
`delete_all` (since the callback would otherwise abort the cascade) and destroys the org. The
pre-flight check above is what *guarantees* that path is only ever reached when there's truly
nothing else in the org to lose.

## 9. Permissions

All four are `app`-scoped, granted only to `owner` in the default role matrix (see
`config/rbac.yml` and `docs/rbac.md` §3):

| Permission | Action | Policy method |
|------------|--------|----------------|
| `app.members.promote` | admin ↔ user toggle (rejects owner targets) | `MembershipPolicy#promote?`/`#demote?` |
| `app.members.remove` | Force-remove a member (rejects owner targets) | `MembershipPolicy#destroy?` |
| `app.members.promote_owner` | Add a co-owner | `MembershipPolicy#promote_to_owner?` |
| `app.members.demote_owner` | Demote an owner to admin (self or peer) | `MembershipPolicy#demote_owner?` |

Because `app.members.promote_owner` and `app.members.demote_owner` were added after the `owner`
role already existed in seeded databases, `RbacRegistry`'s boot-time sync (which only attaches
baseline permissions to a role at *creation* time - see `docs/rbac.md` §14) can't retroactively
grant them. Two one-off data migrations handle the backfill:
`db/migrate/20260712010001_add_promote_owner_permission.rb` and
`db/migrate/20260712020001_add_demote_owner_permission.rb` - both create the `Permission` row
and attach a `RolePermission` to every existing `Role(scope: "app", name: "owner")`. Any future
permission added to an already-seeded role needs the same treatment (`docs/rbac.md` §13).

## 10. Audit events

All logged via `log_audit` (`app/controllers/concerns/audit_logging.rb`) into `AuditLog`
(`app/models/audit_log.rb`):

| Event | Fired when |
|-------|-----------|
| `owner_promoted` | `#promote_to_owner` succeeds |
| `owner_demoted` | `#demote_owner` succeeds (metadata includes `self_initiated: true/false`) |
| `owner_removal_blocked` | Any attempt to remove/demote/leave-as an owner is blocked - by `reject_owner_target` (destroy/promote/demote), `leave`, or `demote_owner`'s last-owner guard |
| `account_deletion_blocked` | `ProfileController#destroy`'s pre-flight check blocks deletion (metadata includes the blocking `organization_ids`) |
| `user_deleted` | Account deletion completes |

`owner_removal_blocked` is intentionally reused across all the "can't touch this owner" paths
rather than split per-action - they're all the same underlying invariant failing.

## 11. Emails

Three independent 6-digit-code confirmation flows, each with its own digest/sent-at column pair
on `users` (never shared - a code for one action can't be replayed against another) and its own
`ACTION_CODE_EXPIRY` constant (all 30 minutes) on `User`:

| Flow | Mailer | Sent to | User methods |
|------|--------|---------|---------------|
| Account deletion | `AccountDeletionMailer#confirm_deletion` | The user deleting their account | `#request_account_deletion_code!` / `#verify_account_deletion_code!` |
| Owner promotion | `OwnershipPromotionMailer#confirm_promotion` | The **acting** owner | `#request_ownership_promotion_code!` / `#verify_ownership_promotion_code!` |
| Owner demotion | `OwnerDemotionMailer#confirm_demotion` | The owner **being demoted** | `#request_owner_demotion_code!` / `#verify_owner_demotion_code!` |

All three follow the same shape: `request_*!` generates a code, stores
`digest_code(code)` (`OpenSSL::HMAC.hexdigest` keyed on `secret_key_base`) and a timestamp via
`update_columns` (no validation/callbacks), and returns the raw code for the mailer.
`verify_*!` rejects if no code was ever sent, if it's past its expiry window, or if
`ActiveSupport::SecurityUtils.secure_compare` doesn't match.

## 12. UI reference

All three code-confirmation dialogs (account deletion, owner promotion, owner demotion) reuse
the exact same frontend building blocks - no new JS was written for any of them:

- **`deletion_confirm_controller.js`** (Stimulus, despite the name it's generic) - takes
  `sendUrlValue`/`expectedEmailValue`, wires a "send code" button, validates the typed email
  against `expectedEmailValue` plus a complete 6-digit code before enabling submit.
- **`shared/_otp_digits`** partial - the 6 individual digit inputs (`name="code[]"`), paired with
  the `two-factor` Stimulus controller for auto-advance/paste handling.

| Dialog | Partial | `expectedEmail` is... |
|--------|---------|------------------------|
| Delete account | `profile/show.html.erb` (inline) | The current user's own email |
| Promote to owner | `org/members/_edit_dialog_content.html.erb` | The member being promoted |
| Demote owner | `org/members/_demote_owner_dialog_content.html.erb` | The owner being demoted (self or peer) |

Members-table row rendering (`org/members/_membership_row.html.erb`) branches on the target's
role: owner rows only ever show the demote control (gated on `can_demote_owner?`); non-owner
rows show the usual edit/remove controls (gated on `can_promote_org_members?`,
`can_promote_to_owner?`, `can_remove_org_members?`). `ApplicationHelper#can_manage_org_members?`
folds all four permission checks together to decide whether the Actions column renders at all.

## 13. Testing

`test/integration/org_members_test.rb` covers, among the pre-existing promote/demote/remove
cases: an owner can't be force-removed even with a second owner present; an owner can't `leave`
directly; self-demotion and peer-demotion both succeed with a valid code; peer-demotion's code
goes to the *target's* email (asserted directly on the delivered mail's `to`); demotion is
blocked for a sole owner; mismatched typed email is rejected; a non-owner is denied outright.

`test/integration/profile_test.rb` covers: a sole owner with other members is blocked from
deleting their account (no `User`/`Organization`/`Membership` destroyed); a non-sole owner can
delete their account leaving the org and other members intact; the original sole-owner-with-no-
other-members case still deletes both.

`test/models/membership_role_test.rb` covers the model-level `prevent_removing_last_owner`
guard directly (destroying the last owner's `MembershipRole`, or the `Membership` itself).

## 14. Known limitations

- **No full "transfer" in one step.** Promotion only ever adds a co-owner; demotion only ever
  removes one. A true one-click "make Alice the owner and demote me" requires calling both
  `#promote_to_owner` and `#demote_owner` as two separate, separately-confirmed actions - by
  design, since collapsing them would mean a single code confirms two different role changes at
  once.
- **No UI to see a pending/unclaimed demotion request.** If owner A sends a demotion code to
  owner B and B never acts on it, there's no visible "pending demotion" state anywhere - the
  request just silently expires after 30 minutes. A production app might want to surface this
  (e.g. a banner on B's dashboard: "A requested to demote you from owner").
- **Peer-demotion has no way to notify the initiator of the outcome.** Owner A doesn't get told
  whether B ever completed (or ignored) the demotion A started - A would need to check the
  members table themselves.
