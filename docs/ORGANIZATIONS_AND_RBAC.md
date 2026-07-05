# Authorization Architecture — RBAC & Multi-Tenant Organizations

This is a reference for how authorization is designed in this app: the role/permission system
already implemented, and the Organization/Membership (multi-tenant) layer designed to sit on
top of it. This app is a **SaaS template** meant to be forked into many different products, so
this document also records *why* each piece is shaped the way it is, not just what it does —
future forks will each decide how far to take the `app`-scoped side of this system.

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
5. [Signup-time provisioning](#5-signup-time-provisioning)
6. [`Current.organization`](#6-currentorganization)
7. [Audit logging](#7-audit-logging)
8. [Implementation status](#8-implementation-status)
9. [Explicitly deferred](#9-explicitly-deferred)

---

## 1. Overview

Authorization here has two independent axes:

| Axis | Question it answers | Who holds it | Example role |
|---|---|---|---|
| **System scope** | "Can this person operate the SaaS platform itself?" | `User`, directly | `system_admin` |
| **App scope** | "What can this person do inside a given customer's Organization?" | `Membership` (a User's membership in one Organization) | `owner` |

These are deliberately kept separate. A platform operator supporting customers doesn't
automatically get product-level permissions inside every customer's Organization, and a
customer's own admin/owner role has no bearing on the platform itself. The same `Role` and
`Permission` models back both axes — only the join table differs (`UserRole` for system scope,
`MembershipRole` for app scope).

## 2. RBAC: Role, Permission, and the `system`/`app` scope split

**`roles`**: `name`, `scope` (enum: `app` default / `system`), `description`, `permanent`
(boolean — blocks rename/delete via `before_update`/`before_destroy` guards, regardless of
caller: console, admin UI, rake task). Unique index on `[:scope, :name]`, so `app`-scope and
`system`-scope roles live in separate namespaces even if they share a name.

**`permissions`**: `key` (dot-namespaced string, e.g. `system.users.manage`,
`app.organization.manage`), `description`. New capabilities are added by inserting rows — no
authorization-layer code changes needed.

**`role_permissions`**: join table, `role_id` + `permission_id`.

Two separate assignment mechanisms, one per scope, each validated to reject the other scope's
roles:

- **`UserRole`** (`user_id`, `role_id`, nullable `granted_by_id`): assigns **`system`-scoped**
  roles directly to a `User`. This is how `system_admin` is granted.
- **`MembershipRole`** (`membership_id`, `role_id`, nullable `granted_by_id`): assigns
  **`app`-scoped** roles to a `Membership` (i.e. to a specific User-in-a-specific-Organization
  pairing). This is how `owner` is granted.

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
require_role(name, scope: nil, **opts)     # before_action gate on a named role
require_permission(key, **opts)            # before_action gate on a permission key
require_system_admin(**opts)               # sugar for require_role(Role::SYSTEM_ADMIN, scope: :system)
```

All three funnel into `deny_authorization!`, which logs an `authorization_denied` audit event
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

## 5. Signup-time provisioning

Every user gets exactly one personal Organization, created atomically with their `User` row —
there is no "bare user with no org" state anywhere else in the app to design around.

`Organization.create_personal_for!(user)`: creates the Organization, its sole Membership, and
grants the `owner` role (`scope: :app, permanent: true`, seeded via `find_or_create_by!` so it
doesn't hard-depend on `db:seed` having run). Name and slug are derived from the email
local-part (registration only collects email/password — there's no name to use instead), with
collision handling (`base`, `base-2`, `base-3`, ... then a random suffix) since different email
domains sharing a local part is an expected case, not an edge case.

`ConfirmationsController#create` is the one place a real `User` row is first persisted
(registration only creates a token-backed `PendingRegistration` until the confirmation code is
verified). User creation and org provisioning are wrapped in one transaction, so a failure in
either rolls back both — a user is never left without an organization, and the pending
registration survives so the user can safely retry.

## 6. `Current.organization`

`Current` (`app/models/current.rb`, an `ActiveSupport::CurrentAttributes`) gains an
`organization` attribute, set once per request by a `CurrentOrganization` controller concern:

```ruby
Current.organization = current_user&.organizations&.first
```

Since every user has exactly one Organization today, `.first` is unambiguous. This
deliberately isolates the *one* lookup that changes when real multi-org switching is built —
everything downstream just reads `Current.organization`.

## 7. Audit logging

Reuses the existing `AuditLog` model and `log_audit` controller concern. New `event_type`
values: `role_granted` / `role_revoked` (shared between `UserRole` and `MembershipRole` grants —
`organization_id` in metadata disambiguates which), `authorization_denied`,
`organization_created`, `membership_created`, `membership_destroyed` (the last added ahead of
there being a removal flow, since it costs nothing to have the enum value ready).

## 8. Implementation status

| Piece | Status |
|---|---|
| `Role`, `Permission`, `RolePermission`, `UserRole`, `system`/`app` scope | **Implemented** |
| `system_admin` role, `Admin::` namespace, bootstrap rake task | **Implemented** |
| `Organization`, `Membership`, `MembershipRole` | **Designed, not yet implemented** |
| Signup-time auto-provisioning of a personal Organization | **Designed, not yet implemented** |
| `Current.organization` | **Designed, not yet implemented** |

## 9. Explicitly deferred

Not part of this design, and not blocked by it — all additive later:

- **Organization invites** (inviting a second user into an existing org) — `Membership` has no
  `status`/`invited_by_id` columns yet on purpose.
- **Org-switcher UI** / stored "current organization" selection — `Current.organization` is a
  `.first` lookup until a user can belong to more than one org in practice.
- **Slug- or subdomain-based page routing** — the slug format is chosen to be routing-ready, but
  no routes are built around it yet.
- **Billing/subscription attachment to `Organization`.**
- **`Admin::OrganizationsController`** for platform-operator visibility into tenant orgs.
- **"Prevent removing the last owner" guard** — unreachable today since there's no
  invite/removal flow yet; revisit when one ships.
