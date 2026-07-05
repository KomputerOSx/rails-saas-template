# Authorization Architecture — RBAC & Multi-Tenant Organizations

This is a reference for how authorization is designed in this app: the role/permission system,
the Organization/Membership (multi-tenant) layer, the `owner`/`admin`/`user` role hierarchy, and
the invite flow. This app is a **SaaS template** meant to be forked into many different
products, so this document also records *why* each piece is shaped the way it is, not just what
it does — future forks will each decide how far to take the `app`-scoped side of this system.

> **Note on `docs/AUTHENTICATION_AND_SECURITY.md`**: that file is leftover documentation for a
> different, unrelated app (a pharmacy/kiosk system called RxTerminal) that ended up in this
> repo's `docs/` folder. It is not a description of this app — don't use it as a reference for
> anything here, including its multi-tenant/RBAC section, which describes a different data model
> (a single `belongs_to :organisation` on `User`, not the `Membership` join model below).

## Contents

1. [Overview](#1-overview)
2. [RBAC: Role, Permission, and the `system`/`app` scope split](#2-rbac-role-permission-and-the-systemapp-scope-split)
3. [The `system_admin` platform-operator role and `Admin::` namespace](#3-the-system_admin-platform-operator-role-and-admin-namespace)
4. [Organizations & Memberships (multi-tenancy)](#4-organizations--memberships-multi-tenancy)
5. [The owner/admin/user role hierarchy](#5-the-owneradminuser-role-hierarchy)
6. [The owner-protection guard](#6-the-owner-protection-guard)
7. [Signup-time provisioning](#7-signup-time-provisioning)
8. [`Current.organization`](#8-currentorganization)
9. [Invite flow](#9-invite-flow)
10. [Org-facing members management (`Org::` namespace)](#10-org-facing-members-management-org-namespace)
11. [Audit logging](#11-audit-logging)
12. [Implementation status](#12-implementation-status)
13. [Explicitly deferred](#13-explicitly-deferred)

---

## 1. Overview

Authorization here has two independent axes:

| Axis | Question it answers | Who holds it | Example role |
|---|---|---|---|
| **System scope** | "Can this person operate the SaaS platform itself?" | `User`, directly | `system_admin` |
| **App scope** | "What can this person do inside a given customer's Organization?" | `Membership` (a User's membership in one Organization) | `owner`, `admin`, `user` |

These are deliberately kept separate. A platform operator supporting customers doesn't
automatically get product-level permissions inside every customer's Organization, and a
customer's own admin/owner role has no bearing on the platform itself — a `system_admin` has no
`Membership` in any customer's org unless they're separately invited into one like anyone else,
and no admin UI exists for a platform operator to browse into tenant orgs (`Admin::` has no
`OrganizationsController`). The same `Role` and `Permission` models back both axes — only the
join table differs (`UserRole` for system scope, `MembershipRole` for app scope).

## 2. RBAC: Role, Permission, and the `system`/`app` scope split

**`roles`**: `name`, `scope` (enum: `app` default / `system`), `description`, `permanent`
(boolean — blocks rename/delete via `before_update`/`before_destroy` guards, regardless of
caller: console, admin UI, rake task). Unique index on `[:scope, :name]`, so `app`-scope and
`system`-scope roles live in separate namespaces even if they share a name.

**`permissions`**: `key` (dot-namespaced string, e.g. `system.users.manage`,
`app.organization.manage`), `description`. New capabilities are added by inserting rows — no
authorization-layer code changes needed. A permission key has no behavior of its own; it only
matters because seed data links it to a `Role` (via `role_permissions`) and a controller action
guards itself with the same string (via `require_permission`/`require_organization_permission`).

**`role_permissions`**: join table, `role_id` + `permission_id`.

Two separate assignment mechanisms, one per scope, each validated to reject the other scope's
roles:

- **`UserRole`** (`user_id`, `role_id`, nullable `granted_by_id`): assigns **`system`-scoped**
  roles directly to a `User`. This is how `system_admin` is granted.
- **`MembershipRole`** (`membership_id`, `role_id`, nullable `granted_by_id`): assigns
  **`app`-scoped** roles to a `Membership` (i.e. to a specific User-in-a-specific-Organization
  pairing). This is how `owner`/`admin`/`user` are granted.

Each join model validates its role's scope (`role.system?` / `role.app?`) so the two mechanisms
can't be crossed by mistake — granting an `app`-scoped role via `UserRole`, or a `system`-scoped
role via `MembershipRole`, raises `ActiveRecord::RecordInvalid`.

`User` and `Membership` expose the same instance API shape:

```ruby
has_role?(name, scope: nil)
has_permission?(key)
grant_role!(role, granted_by: nil)
revoke_role!(role)
```

`User#has_permission?` additionally takes an `organization:` keyword — with an org, it
delegates to that membership; without one, it checks only `user_roles` (i.e. system scope),
which is exactly today's behavior and keeps every existing `system`-scope call site (e.g.
`Authorization#require_permission!`) unaffected by the addition of Organizations.

## 3. The `system_admin` platform-operator role and `Admin::` namespace

`Role::SYSTEM_ADMIN = "system_admin"` is a permanent, seeded `system`-scope role representing
the SaaS operator. `app/controllers/concerns/authorization.rb` provides the authorization DSL:

```ruby
require_role(name, scope: nil, **opts)             # before_action gate on a named role
require_permission(key, **opts)                    # before_action gate on a system-scope permission key
require_system_admin(**opts)                       # sugar for require_role(Role::SYSTEM_ADMIN, scope: :system)
require_organization_permission(key, **opts)       # before_action gate on an app-scope permission, checked against Current.organization
```

All four funnel into `deny_authorization!`, which logs an `authorization_denied` audit event
and redirects. `Admin::BaseController` calls `require_system_admin` once, and every controller
under the `Admin::` namespace (`app/controllers/admin/*`) inherits from it — dashboard, user
list + role grant/revoke, a read-only role catalog, and an audit log viewer. Bootstrapping the
first `system_admin` (no UI exists for this, deliberately) is done via
`bin/rails rbac:grant_system_admin[email]` (`lib/tasks/rbac.rake`) or the `db/seeds.rb`
`SYSTEM_ADMIN_EMAIL` env-gated dev convenience path.

## 4. Organizations & Memberships (multi-tenancy)

**`Organization`**: `name`, `slug` (unique, lowercase alnum + internal hyphens, DNS-label-safe,
reserved-word-blocked — chosen so it's ready for slug-based routing later without
reformatting). No `owner_id` column: ownership is just the `app`-scoped `owner` `Role`, granted
through a `Membership`, so transferring ownership later is a role grant/revoke, not a schema
change or data migration. No status/billing columns yet — out of scope until a product actually
needs them.

**`Membership`**: join between `User` and `Organization` (`user_id`, `organization_id`, unique
on the pair). This is where `app`-scoped roles attach (via `MembershipRole`), because the same
user can hold different roles in different Organizations — a global `User`-level role wouldn't
be able to express that.

## 5. The owner/admin/user role hierarchy

Three seeded `app`-scope roles (`db/seeds.rb`):

| Role | Permanent? | Permissions | Who has it |
|---|---|---|---|
| `owner` | Yes | `app.members.invite`, `app.members.remove`, `app.members.promote`, `app.organization.manage`, `app.billing.manage` | Whoever created the Organization (see §7). Exactly one per org today. |
| `admin` | No | `app.members.invite`, `app.members.remove` | Promoted from `user` by an `owner`. |
| `user` | No | (none) | The default role for invited members. |

`admin`'s permission set is just the plain array literal in `db/seeds.rb` — nothing in the
codebase branches on the string `"admin"`. Changing what admins can do (e.g. adding
`app.billing.manage`) is a one-line seed change, not a code change. `owner` is `permanent: true`
(the Role row itself can't be renamed/deleted); `admin`/`user` are not, since a downstream fork
may rename or restructure them.

Promotion/demotion (`Org::MembersController#promote`/`#demote`) is gated by
`app.members.promote`, which only `owner` holds — an `admin` can invite and remove plain
members but cannot create other admins or touch anyone's role. Both actions explicitly refuse to
target a membership that holds the `owner` role (see §6).

## 6. The owner-protection guard

The founding owner can never be demoted or removed while they're the organization's only owner.
This lives in `app/models/membership_role.rb` as a `before_destroy` callback (the same
`throw :abort` pattern `Role#permanent` already uses):

```ruby
def prevent_removing_last_owner
  return unless role.name == Role::APP_OWNER

  other_owners = membership.organization.membership_roles
    .joins(:role).where(roles: { scope: "app", name: Role::APP_OWNER })
    .where.not(id: id)

  if other_owners.none?
    errors.add(:base, "cannot remove the organization's last owner")
    throw :abort
  end
end
```

**Actual observed behavior (verified against Rails 8.1.3, not assumed from docs)**: destroying
the `MembershipRole` directly, or destroying the parent `Membership` (which cascades into it via
`dependent: :destroy`), both simply return `false` — neither raises. The `:abort` thrown inside
the nested callback rolls back the shared transaction, and `Membership#destroy` reflects that as
a plain falsy return. **Callers must check the boolean return value**, not rescue an exception —
`Org::MembersController#destroy` does exactly this, logging `owner_removal_blocked` on failure
rather than reading `membership.errors` (which doesn't inherit the child `MembershipRole`'s
errors).

**Ownership transfer is not implemented in this template** — the code comment right after the
guard marks the extension point: grant the `owner` role to the new owner's Membership *first*,
then revoke the previous owner's `MembershipRole`. At that point the guard's `other_owners` query
finds the new owner and permits the revoke, so no change to the guard itself is needed — just a
new controller action performing that grant-then-revoke pair inside one transaction.

## 7. Signup-time provisioning

Every user gets exactly one personal Organization, created atomically with their `User` row —
there is no "bare user with no org" state anywhere else in the app to design around.

`Organization.create_personal_for!(user)`: creates the Organization, its sole Membership, and
grants the `owner` role (`scope: :app, permanent: true`, seeded via `find_or_create_by!` so it
doesn't hard-depend on `db:seed` having run). Name and slug are derived from the email
local-part (registration only collects email/password — there's no name to use instead), with
collision handling (`base`, `base-2`, `base-3`, ... then a random suffix on a residual race) since
different email domains sharing a local part is an expected case, not an edge case.

`ConfirmationsController#create` is the one place a real `User` row is first persisted
(registration only creates a token-backed `PendingRegistration` until the confirmation code is
verified). User creation and org provisioning are wrapped in one transaction, so a failure in
either rolls back both — a user is never left without an organization, and the pending
registration survives so the user can safely retry.

## 8. `Current.organization`

`Current` (`app/models/current.rb`, an `ActiveSupport::CurrentAttributes`) gains an
`organization` attribute, set once per request by a `CurrentOrganization` controller concern:

```ruby
Current.organization = current_user&.organizations&.first
```

Since a user can belong to more than one Organization once invites are accepted (see §9),
`.first` is a deliberate simplification, not a correctness guarantee — it picks *a* organization
the user belongs to, not necessarily the one they most recently interacted with. This is the one
lookup that a real multi-org switcher (URL slug, session-stored selection) would replace later;
everything downstream just reads `Current.organization`.

## 9. Invite flow

**`OrganizationInvitation`** (`app/models/organization_invitation.rb`) mirrors
`PasswordResetToken`'s shape — DB-backed (not cache-backed like the short-lived
`PendingRegistration`), because invitations need to be listable/revocable and can be outstanding
for days: `organization_id`, `email`, `role_id` (always `user` from the invite form — promotion
to admin is a separate action after joining), `invited_by_id`, `token_digest` (unique),
`expires_at` (7-day expiry), `accepted_at`, `revoked_at`. A partial unique index on
`[organization_id, email]` (where outstanding) means re-inviting an email cleanly supersedes a
prior pending invite. `OrganizationInvitationMailer` sends a link to a GET show page, not
directly to the accept action, because that page has to branch on the invitee's auth state.

**`InvitationsController`** (public, `allow_unauthenticated_access` on `show`/`accept`):
- `GET /invitations/:token` — authenticated + email matches → show an accept confirmation;
  authenticated + email mismatch → tell them to sign out; not authenticated → stash
  `session[:pending_invitation_token]` and redirect to login (existing account) or registration
  prefilled with the invited email (no account yet).
- `POST /invitations/:token/accept` — requires authentication + matching email, calls
  `invitation.accept!(current_user)`.

**The `reset_session` gotcha**: two existing flows call `reset_session` (anti session-fixation)
*between* the point the invite token is stashed and the point it's read back:
`SessionsController#begin_two_factor_for` (2FA login) and `ConfirmationsController#create`
(right after creating the `User` row). Both silently wipe `session[:pending_invitation_token]`
if not handled. The fix: capture the value into a local/temp before each `reset_session` call and
restore or reuse it afterward. **If you add another `reset_session` call anywhere in the
auth flow, check whether it needs the same treatment.** A shared `InvitationResumption` concern
(`resume_pending_invitation_for(user, token:)`) is included in both `SessionsController` and
`ConfirmationsController`, called at the point each successfully establishes a session.

A brand-new invitee who has no account yet ends up with **two** Organizations after signing up:
their own personal one (§7, unconditional for every signup) plus the one they were invited into.

## 10. Org-facing members management (`Org::` namespace)

Separate from the system-scope `Admin::` namespace — this operates on `Current.organization`,
not the whole platform.

- `Org::BaseController` — redirects if `Current.organization` is unexpectedly blank.
- `Org::MembersController#index` — any member of the org can view the member list and pending
  invitations (not permission-gated); `#destroy` (`app.members.remove`) removes a member,
  rescued into a flash alert if the owner-protection guard blocks it; `#promote`/`#demote`
  (`app.members.promote`, owner-only) switch a member between `admin` and `user`, refusing to
  target an `owner` membership.
- `Org::InvitationsController#create`/`#destroy` (`app.members.invite`) — send or revoke a
  pending invitation. Revoking uses the same permission as sending, since it's part of the
  invitation lifecycle, not the more sensitive "remove an existing member" action.

## 11. Audit logging

Reuses the existing `AuditLog` model and `log_audit` controller concern. `event_type` values
added across this system: `role_granted` / `role_revoked` (shared between `UserRole` and
`MembershipRole` grants — `organization_id` in metadata disambiguates which), `authorization_denied`,
`organization_created`, `membership_created`, `membership_destroyed`,
`organization_invitation_sent`, `organization_invitation_accepted`,
`organization_invitation_revoked`, `owner_removal_blocked`. The last one is deliberately distinct
from `authorization_denied` — the actor *is* authorized to remove members in general, the action
just violates a data invariant; conflating the two would hide "someone tried to remove the sole
owner" inside routine permission-denial noise.

## 12. Implementation status

| Piece | Status |
|---|---|
| `Role`, `Permission`, `RolePermission`, `UserRole`, `system`/`app` scope | **Implemented** |
| `system_admin` role, `Admin::` namespace, bootstrap rake task | **Implemented** |
| `Organization`, `Membership`, `MembershipRole` | **Implemented** |
| `owner`/`admin`/`user` role hierarchy + seeded permissions | **Implemented** |
| Owner-protection guard | **Implemented** |
| Signup-time auto-provisioning of a personal Organization | **Implemented** |
| `Current.organization` | **Implemented** |
| Invite flow (model, mailer, accept endpoint, session resumption) | **Implemented** |
| Org-facing members management (`Org::` namespace) | **Implemented** |

## 13. Explicitly deferred

Not part of this design, and not blocked by it — all additive later:

- **Ownership transfer** — the protective guard is built (§6); the transfer flow itself is not.
- **Org-switcher UI** / stored "current organization" selection — `Current.organization` is a
  `.first` lookup even though a user can now belong to more than one org.
- **Slug- or subdomain-based page routing** — the slug format is chosen to be routing-ready, but
  no routes are built around it yet.
- **Billing/subscription implementation** — `app.billing.manage` is a placeholder permission key
  only; no billing gem or Stripe/Pay integration exists.
- **`Admin::OrganizationsController`** for platform-operator visibility into tenant orgs.
