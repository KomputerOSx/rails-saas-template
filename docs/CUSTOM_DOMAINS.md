# Custom domains

How Growth-plan organizations attach one custom domain, how Caddy issues on-demand
Let's Encrypt certificates, and how the public org site is served on that host.

## Contents

- [Custom domains](#custom-domains)
  - [Contents](#contents)
  - [1. Overview](#1-overview)
  - [2. Plan gate](#2-plan-gate)
  - [3. Data model](#3-data-model)
  - [4. Request flow](#4-request-flow)
  - [5. Rails pieces](#5-rails-pieces)
    - [Internal TLS ask endpoint](#internal-tls-ask-endpoint)
    - [Host resolution middleware](#host-resolution-middleware)
    - [Public site](#public-site)
    - [Org settings UI](#org-settings-ui)
  - [6. Infrastructure (Caddy + Kamal)](#6-infrastructure-caddy--kamal)
  - [7. DNS onboarding](#7-dns-onboarding)
  - [8. Environment variables](#8-environment-variables)
  - [9. Downgrade and cleanup](#9-downgrade-and-cleanup)
  - [10. Testing](#10-testing)
  - [11. Known limitations](#11-known-limitations)

---

## 1. Overview

Orgs on the **Growth** plan can attach **one** custom domain (e.g. `app.acme.com`).
That domain:

1. Points at the app server via DNS (CNAME or A record).
2. Gets a Let's Encrypt certificate via **Caddy on-demand TLS**.
3. Serves a **public** page for that organization (`SitesController`) — today a
   placeholder showing org name/slug/domain; later a shopfront or booking screen.

The authenticated app (dashboard, settings, billing) stays on the **primary host**
(`APP_HOST`). Custom domains are a separate public surface, not a second login host.

Traffic shape:

```
Visitor → DNS → Caddy (:80/:443)
              → ask Rails /internal/domain_validations
              → kamal-proxy (127.0.0.1:3000)
              → Rails → SitesController (custom host)
                     → normal app routes (primary host)
```

## 2. Plan gate

Defined on `Billing::Plans::Plan` as `custom_domain` (boolean). See
[`docs/BILLING.md`](BILLING.md).

| Plan | `custom_domain` |
|---|---|
| Free | `false` |
| Starter | `false` |
| Growth | `true` |

`Organization#custom_domain_allowed?` reads `current_plan.custom_domain?`. Assigning a
domain when the plan does not allow it fails validation with
`"requires the Growth plan"`.

## 3. Data model

Column on `organizations`:

- `custom_domain` — nullable string, **unique** index
- Normalized on save: lowercase, strip, drop leading `www.`
- Format: hostname only (`shop.example.com`), not a URL

Cache key for host → org id lookups: `domain_org_id:#{domain}` (10 minutes). Cleared in
`after_save` when `custom_domain` changes (`Organization#clear_custom_domain_cache`).

## 4. Request flow

1. **Primary host** (`AppHost.primary?`) — normal app routes; middleware is a no-op.
2. **Any other host** — treated as a potential custom domain:
   - `CustomDomainResolver` looks up the org id and sets
     `env["windtunnel.custom_domain_organization_id"]`.
   - `CustomDomainConstraint` sends all paths to `SitesController#show`.
   - Unknown / unconfigured domains get `404`.

`AppHost` (`app/models/app_host.rb`) decides primary vs custom using `APP_HOST`, plus
`localhost` / `127.0.0.1`, and (in development/test) `example.com`.

Production `config.hosts` allows the primary host **or** any value present in
`organizations.custom_domain`. `/up` and `/internal/*` are excluded from host
authorization so health checks and Caddy's ask endpoint keep working.

## 5. Rails pieces

### Internal TLS ask endpoint

- Route: `GET /internal/domain_validations?domain=…`
- Controller: `Internal::DomainValidationsController` (inherits `ActionController::Base`,
  not `ApplicationController`, so auth / browser / onboarding filters never block Caddy)
- Returns `200 OK` only when:
  - Remote IP is private (`127.`, `10.`, `172.`, `192.168.`, or `::1`), and
  - An org owns that `custom_domain`, and
  - That org is still on Growth (`custom_domain_allowed?`)
- Otherwise `401` (non-internal IP) or `404`

This is what stops random domains pointed at the server from burning Let's Encrypt
rate limits.

### Host resolution middleware

`app/middleware/custom_domain_resolver.rb`, registered with
`config.middleware.use CustomDomainResolver` in `config/application.rb`.

### Public site

- `SitesController#show` — unauthenticated, `landing` layout
- View: `app/views/sites/show.html.erb` (org name, slug, custom domain)
- Routes (constrained): custom-domain `root` + catch-all `*path` → `sites#show`

### Org settings UI

Section on `/org/settings` (`app/views/org/settings/_custom_domain_section.html.erb`):

- **Growth, no domain** — form + DNS instructions
- **Growth, domain set** — current domain, SSL note, Remove
- **Not Growth** — locked copy + link to `/billing`

Mutations go through `Org::CustomDomainsController` (`POST` / `DELETE`
`/org/custom_domain`), authorized with `OrganizationPolicy#update?`
(`app.organization.manage`). Audit events: `custom_domain_updated`,
`custom_domain_removed`.

## 6. Infrastructure (Caddy + Kamal)

Caddy terminates TLS on the host; **kamal-proxy stays enabled** for gapless deploys but
binds to localhost without SSL:

```yaml
# config/deploy.yml (excerpt)
proxy:
  ssl: false
  run:
    http_port: 3000
    https_port: 3001
    bind_ips:
      - 127.0.0.1

accessories:
  caddy:
    image: caddy:2-alpine
    host: 192.168.0.1   # your server IP
    network: host
    files:
      - config/Caddyfile:/etc/caddy/Caddyfile
    volumes:
      - caddy_data:/data
      - caddy_config:/config
```

[`config/Caddyfile`](../config/Caddyfile):

- Global `on_demand_tls` with `ask http://127.0.0.1:3000/internal/domain_validations`
- Primary host block → `reverse_proxy 127.0.0.1:3000`
- `:443` with `tls { on_demand }` for customer domains
- `:80` redirects to HTTPS

**Persist `caddy_data`.** If that volume is lost, Caddy re-issues every customer cert and
can hit Let's Encrypt rate limits immediately.

First boot: set `ACME_EMAIL` / `APP_HOST` on the accessory, then
`bin/kamal accessory boot caddy` (and `reboot` after Caddyfile changes).

## 7. DNS onboarding

Shown in org settings (values from `AppHost.primary_host` / `AppHost.server_ip`):

| Domain type | Record | Target |
|---|---|---|
| Subdomain (`app.example.com`) | CNAME | Primary app host (`APP_HOST`) |
| Apex / root (`example.com`) | A | Server public IP (`APP_SERVER_IP`) |

SSL is issued automatically the first time HTTPS hits Caddy for an allowed domain, once
DNS resolves to the server.

## 8. Environment variables

| Variable | Used by | Purpose |
|---|---|---|
| `APP_HOST` | Rails (`AppHost`), Caddy primary site block | Canonical app hostname |
| `APP_SERVER_IP` | Rails settings DNS copy | Apex A-record target shown to owners |
| `ACME_EMAIL` | Caddy | Let's Encrypt account email |

Set the Rails vars under `env.clear` in `config/deploy.yml`, and the Caddy vars under
`accessories.caddy.env.clear`.

## 9. Downgrade and cleanup

When a subscription ends or drops below Growth, `Billing::ReconcileOrganizationJob`
calls `Organization#clear_custom_domain_if_disallowed!`, which nulls `custom_domain`.
Caddy's next ask then gets `404` and will not renew/issue for that host.

Validation only enforces the Growth requirement when `custom_domain` is **changing**, so
a dirty org row with a leftover domain does not block unrelated updates; reconcile clears
it.

## 10. Testing

| Area | File |
|---|---|
| Model / plan / cache | `test/models/organization_custom_domain_test.rb` |
| Plan flag | `test/models/billing/plans_test.rb` |
| TLS ask | `test/integration/internal_domain_validations_test.rb` |
| Public site | `test/integration/sites_controller_test.rb` |
| Settings UI / permissions | `test/integration/org_custom_domains_test.rb` |
| Downgrade clear | `test/jobs/billing/reconcile_organization_job_test.rb` |

Use `with_active_subscription(org, Billing::Plans::GROWTH)` when asserting Growth-only
behavior (see `test/test_helper.rb`).

## 11. Known limitations

- One domain per organization (no aliases / www + apex pair as separate rows).
- No DNS TXT verification step — ownership is implied by DNS pointing here plus the
  Growth-gated ask endpoint.
- Public site is a placeholder; shopfront/booking UI is out of scope for this feature.
- Apex domains need an A record (or ALIAS/ANAME at the DNS provider); plain CNAME at
  the zone apex is not valid DNS.
