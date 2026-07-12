# Role-based access control (RBAC)

How permissions, roles, and Pundit policies work in this template, how org context affects
authorization, and how to gate UI and controller actions.

## Contents

- [Role-based access control (RBAC)](#role-based-access-control-rbac)
  - [Contents](#contents)
  - [1. Overview](#1-overview)
  - [2. Data model](#2-data-model)
  - [3. Permission catalog](#3-permission-catalog)
  - [4. Role scopes](#4-role-scopes)
  - [5. Resolving permissions](#5-resolving-permissions)
  - [6. Organization context](#6-organization-context)
  - [7. Pundit policies](#7-pundit-policies)
  - [8. Controller enforcement](#8-controller-enforcement)
  - [9. Hiding UI by permission](#9-hiding-ui-by-permission)
  - [10. Invitations and role assignment](#10-invitations-and-role-assignment)
  - [11. Owner safeguards](#11-owner-safeguards)
  - [12. Admin UI for roles and permissions](#12-admin-ui-for-roles-and-permissions)
  - [13. Adding a new permission](#13-adding-a-new-permission)
  - [14. Boot-time sync](#14-boot-time-sync)
  - [15. Rake tasks](#15-rake-tasks)
  - [16. Testing](#16-testing)
  - [17. Known gaps](#17-known-gaps)

---

## 1. Overview

This template uses **permission-based RBAC** with [Pundit](https://github.com/varvet/pundit)
for controller authorization.

- **Permissions** are atomic capabilities (e.g. `app.members.invite`).
- **Roles** are named bundles of permissions (e.g. `owner`, `admin`, `user`).
- **Users** receive roles in one of two scopes:
  - **`system`** — platform-wide operator roles, granted directly on the user.
  - **`app`** — organization-scoped roles, granted on a **membership** (user ↔ org join).

The organization is the unit of tenancy. App-scoped permissions are always evaluated against
the **currently selected organization** (`Current.organization`), not globally across all orgs
a user belongs to.

Authorization flow:

```
HTTP request
  → Authentication (session → Current.user)
  → CurrentOrganization (session → Current.organization)
  → Controller calls authorize
  → Pundit policy
  → User#has_permission?(key, organization: ...)
  → Membership roles (app scope) or User roles (system scope)
  → Role → RolePermission → Permission
```

On denial, `ApplicationController` rescues `Pundit::NotAuthorizedError`, logs an audit event,
and redirects to root with an alert.

**Key files**

| Purpose | Path |
|---------|------|
| Permission catalog | `config/rbac.yml` |
| Boot-time sync | `config/initializers/rbac_registry.rb`, `app/models/rbac_registry.rb` |
| Org context | `app/controllers/concerns/current_organization.rb` |
| Policies | `app/policies/` |
| Permission resolver | `app/models/user.rb`, `app/models/membership.rb` |

---

## 2. Data model

```
User ──< UserRole >── Role (scope: system) ──< RolePermission >── Permission
User ──< Membership >── Organization
Membership ──< MembershipRole >── Role (scope: app) ──< RolePermission >── Permission
OrganizationInvitation ──> Role (app-scoped)
```

| Table | Purpose |
|-------|---------|
| `permissions` | Atomic capability keys (`key`, `description`) |
| `roles` | Named role per scope (`name`, `scope`, `permanent`, `description`) |
| `role_permissions` | Join: which permissions a role grants |
| `user_roles` | System roles on a user (`granted_by_id` optional) |
| `membership_roles` | App roles on a membership (`granted_by_id` optional) |
| `organization_invitations` | Pending invite with target role, token, expiry |

**Scope enforcement on join tables**

- `UserRole` validates the role is `system`-scoped (`app/models/user_role.rb`).
- `MembershipRole` validates the role is `app`-scoped (`app/models/membership_role.rb`).

A user can belong to many organizations with different roles in each. System roles apply
platform-wide and are independent of org membership.

---

## 3. Permission catalog

The canonical list lives in `config/rbac.yml`:

```yaml
permissions:
  system.users.manage: "Manage user accounts"
  system.roles.manage: "View/manage roles and permissions"
  system.audit_logs.view: "View audit logs"
  system.billing.manage: "Manage platform-wide billing (price migrations, grandfathering)"
  system.email_campaigns.manage: "Compose and send platform-wide email campaigns"
  app.members.invite: "Invite people to the organization"
  app.members.remove: "Remove members from the organization"
  app.members.promote: "Promote/demote members between admin and user"
  app.members.promote_owner: "Promote a member to co-owner of the organization"
  app.organization.manage: "Manage organization settings"
  app.billing.manage: "Manage billing and subscription"
```

Permission keys must match `\A[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+\z` (dot-separated segments).

### Default app role matrix

| Permission | `owner` | `admin` | `user` |
|------------|:-------:|:-------:|:------:|
| `app.members.invite` | ✓ | ✓ | |
| `app.members.remove` | ✓ | ✓ | |
| `app.members.promote` | ✓ | | |
| `app.members.promote_owner` | ✓ | | |
| `app.organization.manage` | ✓ | | |
| `app.billing.manage` | ✓ | | |

### Default system roles

| Role | Permissions |
|------|-------------|
| `system_admin` (permanent) | All `system.*` permissions |
| `system_user` (permanent) | `system.users.manage`, `system.roles.manage` |

`system.email_campaigns.manage` is granted to `system_admin` only — mass-emailing every platform
user is high-blast-radius enough to sit alongside `system.billing.manage`, which `system_user`
also lacks. See `docs/plans/email-campaigns.md` for the feature this permission gates.

---

## 4. Role scopes

Roles have a `scope` enum: `app` or `system` (`app/models/role.rb`).

**App roles** (`owner`, `admin`, `user`) are granted via `Membership#grant_role!` and checked
with `organization:` passed to `has_permission?`.

**System roles** (`system_admin`, `system_user`) are granted via `User#grant_role!` and checked
without an organization argument. They gate the `Admin::` namespace.

**Permanent roles** (`permanent: true` in `config/rbac.yml`) cannot be renamed or deleted.
The `owner` app role and both system roles are permanent.

Role name constants are defined on `Role`:

```ruby
Role::APP_OWNER   # "owner"
Role::APP_ADMIN   # "admin"
Role::APP_USER    # "user"
Role::SYSTEM_ADMIN # "system_admin"
Role::SYSTEM_USER  # "system_user"
```

---

## 5. Resolving permissions

### User level

```ruby
# app/models/user.rb
def has_permission?(key, organization: nil)
  if organization
    memberships.find_by(organization: organization)&.has_permission?(key) || false
  else
    roles.joins(:permissions).exists?(permissions: { key: key.to_s })
  end
end
```

- **With `organization:`** — looks up the user's membership in that org and checks its roles.
  Returns `false` if the user is not a member.
- **Without `organization:`** — checks system-scoped `UserRole` permissions only.

### Membership level

```ruby
# app/models/membership.rb
def has_permission?(key)
  roles.joins(:permissions).exists?(permissions: { key: key.to_s })
end
```

Permissions from all roles on the membership are unioned. If a membership somehow holds
multiple app roles, any role that grants the permission is sufficient.

### Helper methods

```ruby
user.has_role?("admin", scope: :app)          # role name check (any scope if omitted)
user.system_operator?                          # has any system-scoped role
user.system_admin?                             # has system_admin role specifically
membership.has_role?("owner", scope: :app)
```

Prefer `has_permission?` over `has_role?` for authorization — permissions are the stable
contract; role names are labels that can change.

---

## 6. Organization context

`CurrentOrganization` (`app/controllers/concerns/current_organization.rb`) runs on every
request and sets `Current.organization` from the session:

```ruby
organization = current_user.organizations
  .find_by(id: session[:current_organization_id]) || current_user.organizations.first
session[:current_organization_id] = organization&.id
Current.organization = organization
```

Users switch orgs via `Org::SwitchesController#create`, which updates
`session[:current_organization_id]`.

`current_membership` is exposed as a helper method:

```ruby
def current_membership
  return nil unless Current.organization && current_user
  current_user.memberships.find_by(organization: Current.organization)
end
```

**Important:** App-scoped permission checks must always pass the selected org:

```ruby
current_user.has_permission?("app.members.invite", organization: Current.organization)
```

Checking `has_permission?("app.members.invite")` without `organization:` will always return
`false` for app permissions (they live on memberships, not users directly).

### Org creation

When a user signs up, `Organization.create_personal_for!(user)` creates an org, a membership,
and grants the permanent `owner` role:

```ruby
membership = organization.memberships.create!(user: user)
membership.grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_OWNER))
```

---

## 7. Pundit policies

Pundit is included in `ApplicationController`. There is no custom `pundit_user` — policies
receive `current_user` automatically.

`ApplicationPolicy` denies everything by default. Each resource policy overrides the actions
it cares about.

### SystemPolicy — Admin:: namespace

Used with a symbolic record (`:system`), not an ActiveRecord model:

```ruby
authorize :system, :manage?, policy_class: SystemPolicy
```

| Predicate | Checks |
|-----------|--------|
| `manage?` | Any system-scoped role (`user.system_operator?`) — namespace entry gate |
| `manage_users?` | `system.users.manage` |
| `manage_roles?` | `system.roles.manage` |
| `view_audit_logs?` | `system.audit_logs.view` |
| `manage_billing?` | `system.billing.manage` |

Two-tier gating: `Admin::BaseController` requires `manage?` (any system operator). Individual
controllers then require the specific permission (e.g. `Admin::UsersController` requires
`manage_users?`).

### OrganizationPolicy

```ruby
def update?
  user&.has_permission?("app.organization.manage", organization: record) || false
end
```

Used for org rename (`Org::OrganizationsController#update`) and feature flags
(`Org::FeaturesController`).

### MembershipPolicy

| Action | Permission |
|--------|------------|
| `destroy?` | `app.members.remove` |
| `promote?` | `app.members.promote` |
| `demote?` | `app.members.promote` |
| `promote_to_owner?` | `app.members.promote_owner` |

Pundit maps controller action names to policy methods automatically:

```ruby
authorize @membership  # checks MembershipPolicy#destroy? for DELETE, etc.
```

### OrganizationInvitationPolicy

Both invite and revoke require `app.members.invite`:

```ruby
def permission?
  user&.has_permission?("app.members.invite", organization: organization) || false
end
```

For `create?`, the record is the `Organization` (invitation doesn't exist yet). For
`destroy?`, the record is the `OrganizationInvitation`.

### BillingPolicy

Both `show?` and `manage?` require `app.billing.manage` on the organization.

### verify_authorized

`Org::BaseController`, `Admin::BaseController`, and `BillingController` run
`after_action :verify_authorized`. Every action must call `authorize` or explicitly
`skip_authorization`.

---

## 8. Controller enforcement

### Org-facing controllers

| Controller / action | Policy | Permission | Notes |
|---------------------|--------|------------|-------|
| `Org::SettingsController#index` | — | — | `skip_authorization`; any member can view |
| `Org::OrganizationsController#update` | `OrganizationPolicy#update?` | `app.organization.manage` | Rename org |
| `Org::FeaturesController` | `OrganizationPolicy#update?` | `app.organization.manage` | Feature flags |
| `Org::InvitationsController#create` | `OrganizationInvitationPolicy#create?` | `app.members.invite` | Always assigns `user` role |
| `Org::InvitationsController#destroy` | `OrganizationInvitationPolicy#destroy?` | `app.members.invite` | Revoke pending invite |
| `Org::MembersController#destroy` | `MembershipPolicy#destroy?` | `app.members.remove` | Remove another member |
| `Org::MembersController#promote/demote` | `MembershipPolicy#promote?/demote?` | `app.members.promote` | Change admin ↔ user |
| `Org::MembersController#promote_to_owner` | `MembershipPolicy#promote_to_owner?` | `app.members.promote_owner` | Add a co-owner; requires typed-email + emailed-code confirmation |
| `Org::MembersController#leave` | — | — | `skip_authorization`; self-removal always allowed |
| `BillingController` + nested | `BillingPolicy` | `app.billing.manage` | Show + all mutations |

### Admin controllers

| Controller | Policy predicate |
|------------|-----------------|
| `Admin::BaseController` (all) | `SystemPolicy#manage?` |
| `Admin::UsersController` | `manage_users?` |
| `Admin::UserRolesController` | `manage_users?` |
| `Admin::RolesController` | `manage_roles?` |
| `Admin::PermissionsController` | `manage_roles?` |
| `Admin::AuditLogsController` | `view_audit_logs?` |
| `Admin::PriceMigrationsController` | `manage_billing?` |
| `Admin::OrganizationGrandfathersController` | `manage_billing?` |

---

## 9. Hiding UI by permission

Controllers are the source of truth for security. View checks are for UX — hiding controls
the user cannot use.

There is no dedicated permission helper. Use `current_user.has_permission?` directly in ERB,
always passing `organization: Current.organization` for app-scoped permissions:

```erb
<% if current_user.has_permission?("app.organization.manage", organization: Current.organization) %>
  <!-- edit org name button -->
<% end %>
```

Reference: `app/views/org/settings/_name_editor.html.erb`.

### Sidebar navigation

`app/views/shared/_sidebar_nav.html.erb` demonstrates both patterns:

- **Org section** — shown when `current_membership&.roles&.any?` (user has any app role in
  the selected org).
- **Admin items** — each link gated individually:
  ```erb
  <% if current_user.has_permission?("system.users.manage") %>
  ```
- **Admin section** — shown when `current_user.system_operator?`.

### Example: hide pending invitations

The invitations partial (`app/views/org/invitations/_section.html.erb`) currently renders
the table and invite form for all org members. To hide it from users without invite permission:

```erb
<% if current_user.has_permission?("app.members.invite", organization: Current.organization) %>
  <div id="pending_invitations_section" class="mt-10">
    <!-- table + invite form -->
  </div>
<% end %>
```

Both inviting and revoking use `app.members.invite`, so this single check covers the whole
section.

### Optional helper

If you gate many views, extract a helper in `ApplicationHelper`:

```ruby
def can_manage_org_invitations?
  current_user.has_permission?("app.members.invite", organization: Current.organization)
end
```

You can also call Pundit from views (`policy(Current.organization)`), but the direct
`has_permission?` call matches the existing codebase style.

### Permission → UI mapping (org settings)

| UI element | Permission |
|------------|------------|
| Edit org name | `app.organization.manage` |
| Pending invitations (table + form) | `app.members.invite` |
| Member remove / role edit | `app.members.remove` / `app.members.promote` |
| Billing page controls | `app.billing.manage` |

---

## 10. Invitations and role assignment

Invitations carry a target app role. On accept, that role is granted to the new membership.

Flow:

1. User with `app.members.invite` submits email on org settings.
2. `OrganizationInvitation.generate_for!` creates the record (revoking any prior outstanding
   invite for the same email).
3. Email sent with token link.
4. Recipient accepts → `OrganizationInvitation#accept!` creates/finds membership and calls
   `membership.grant_role!(role)`.

The invite form always assigns the `user` role. Promotion to `admin` is a separate action
(`Org::MembersController#promote`) requiring `app.members.promote`.

Member limit is enforced at invite creation and again at acceptance (see `docs/BILLING.md` §7).

---

## 11. Owner safeguards

Several guards prevent an org from being left without an owner:

- **`MembershipRole#prevent_removing_last_owner`** — blocks destroying the last `owner`
  `MembershipRole` in an org.
- **`Org::MembersController#reject_owner_target`** — blocks promote/demote (the admin ↔ user
  toggle) on owners.
- **`Org::MembersController#promote_to_owner`** — the only supported ownership change: adds a
  co-owner (organizations can have multiple owners at once; this never demotes the original
  owner). Gated by `app.members.promote_owner` and requires the acting owner to type the target
  member's email and enter a 6-digit code emailed to their own address
  (`OwnershipPromotionMailer`), mirroring the account-deletion confirmation flow.
- **Member row UI** — edit/remove actions are hidden for members with the `owner` role
  (`app/views/org/members/_membership_row.html.erb`), regardless of the current user's
  permissions.
- **Self-removal (`leave`)** — always allowed, but fails if the user is the sole owner.
- **`ProfileController#destroy` (account deletion)** — a user who is the *sole* owner of an
  organization that still has other members is blocked from deleting their account until they
  promote a co-owner or remove those members. If they're the sole owner **and** the only
  remaining member, deleting their account also destroys the organization (see
  `ProfileController#sole_owner_with_other_members?`).

Full transfer (demoting the original owner as part of promoting a new one) is documented as an
unimplemented extension point in `app/models/membership_role.rb#prevent_removing_last_owner`.

---

## 12. Admin UI for roles and permissions

System operators with `system.roles.manage` can manage roles at `/admin/roles`:

- Create custom app or system roles.
- Attach/detach permissions on existing roles.
- Delete non-permanent roles.

Changes made via the admin UI **persist across deploys**. Boot-time sync only attaches
baseline permissions when a role is first created (see §14).

System operators with `system.users.manage` can grant/revoke system roles on users at
`/admin/users/:id` via `Admin::UserRolesController`.

To bootstrap the first system admin in development or production:

```bash
bin/rails "rbac:grant_system_admin[user@example.com]"
```

See `lib/tasks/rbac.rake`.

---

## 13. Adding a new permission

1. **Add the key and description** to `config/rbac.yml` under `permissions:`.
2. **Assign it to baseline roles** under `roles:` (only affects newly created roles — see §14).
3. **For existing roles in your database**, attach it manually via the admin UI or a migration/
   seed task.
4. **Add a Pundit policy method** (or extend an existing one) that calls
   `has_permission?("your.new.permission", organization: ...)`.
5. **Call `authorize`** in the controller action.
6. **Gate the UI** with the same permission check in views.
7. **Add integration tests** following `test/integration/org_members_test.rb` and
   `test/integration/admin_rbac_enforcement_test.rb`.

Example: adding `app.projects.manage`:

```yaml
# config/rbac.yml
permissions:
  app.projects.manage: "Create and manage projects"

roles:
  app:
    owner:
      permissions: [..., app.projects.manage]
```

```ruby
# app/policies/project_policy.rb
class ProjectPolicy < ApplicationPolicy
  def update?
    user&.has_permission?("app.projects.manage", organization: record.organization) || false
  end
end
```

```ruby
# app/controllers/projects_controller.rb
def update
  authorize @project
  # ...
end
```

```erb
<% if current_user.has_permission?("app.projects.manage", organization: Current.organization) %>
  <%= link_to "Edit", edit_project_path(@project) %>
<% end %>
```

---

## 14. Boot-time sync

`RbacRegistry` (`app/models/rbac_registry.rb`) runs after Rails initializes
(`config/initializers/rbac_registry.rb`):

1. Creates any missing `Permission` records from `config/rbac.yml`.
2. Creates any missing `Role` records.
3. Attaches baseline permissions **only when a role is first created**.

Once a role exists, boot sync never modifies its permission set. This means:

- New permissions added to `config/rbac.yml` appear in the database on deploy.
- Existing roles do **not** automatically receive new permissions — update them via the admin
  UI or a one-off task.
- Admin edits to role permissions survive every deploy.

This runs on every boot (not just `db:seed`), so Kamal deploys to existing databases still
pick up new permission keys.

---

## 15. Rake tasks

| Task | Purpose |
|------|---------|
| `rbac:grant_system_admin[email]` | Grant `system_admin` to a user by email |

Defined in `lib/tasks/rbac.rake`. Creates an audit log entry.

---

## 16. Testing

Integration tests document expected RBAC behavior:

| File | Covers |
|------|--------|
| `test/integration/org_members_test.rb` | Plain user can view settings but not remove; admin can invite/remove but not promote |
| `test/integration/org_organizations_test.rb` | Plain user cannot rename org |
| `test/integration/admin_rbac_enforcement_test.rb` | System permission granularity; namespace vs action gating |
| `test/integration/billing_*_test.rb` | Non-owner blocked from billing mutations |

Pattern for testing authorization:

```ruby
# User without permission gets redirected
assert_no_difference "OrganizationInvitation.count" do
  post org_invitations_path, params: { email: "test@example.com" }
end
assert_redirected_to root_path
```

To simulate permission changes in tests, attach/detach permissions on roles directly:

```ruby
role.permissions.delete(Permission.find_by!(key: "system.users.manage"))
```

---

## 17. Known gaps

Some UI surfaces show controls to all org members even though controllers enforce permissions.
Users without the required permission see the control but get redirected on submit.

| Location | Current UI behavior | Required permission (controller) |
|----------|--------------------|------------------------------------|
| `org/invitations/_section.html.erb` | Table + invite form always visible | `app.members.invite` |
| `org/invitations/_invitation_row.html.erb` | Revoke button always visible | `app.members.invite` |
| `org/members/_membership_row.html.erb` | Edit/remove shown for non-owners | `app.members.remove`, `app.members.promote` |
| `shared/_sidebar_nav.html.erb` — Billing link | Shown to all authenticated users | `app.billing.manage` (billing page) |

Member row actions are gated by **target role** (hide for owners) and **self vs other**, not
by whether the current user holds the relevant permission. Align these with the patterns in
§9 when polishing the UX.

**Security note:** Controller authorization is always enforced regardless of UI state. View
gating is optional UX polish, not a security boundary.
