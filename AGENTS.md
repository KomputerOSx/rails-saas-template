# AGENTS.md

## Cursor Cloud specific instructions

Windtunnel is a single **Rails 8.1** app (Ruby **4.0.5**, SQLite, Hotwire + importmap, Tailwind/DaisyUI). It is a multi-tenant SaaS starter with auth/2FA, organizations, RBAC (Pundit), Stripe billing (Pay), admin panel, notifications, and email campaigns. There is no separate frontend build or external database server.

### Toolchain / environment
- Ruby is managed by **mise** (`mise.toml` pins `ruby 4.0.5`). `mise activate` is wired into `~/.bashrc`, so an interactive/login shell has `ruby`/`bundle` on `PATH`. In a bare non-login shell, prefix commands with `mise exec --` (e.g. `mise exec -- bin/rails ...`).
- `package.json` is empty — there is no npm/yarn/pnpm step; JS is handled by importmap.

### Running the app (services)
- **Dev server:** `bin/dev` (Foreman via `Procfile.dev`) runs Puma on port **3000** plus the Tailwind CSS watcher. This is the only process needed for auth/orgs/admin/RBAC/notifications. `bin/dev` auto-installs the `foreman` gem on first run.
- Web-only alternative: `bin/rails server`. CSS-only: `bin/rails tailwindcss:watch`.
- Background jobs run in-process (`:async`) in development; no separate worker needed. Production-style jobs use `bin/jobs` or `SOLID_QUEUE_IN_PUMA=true`.
- Seeded dev login: **`admin@mail.com` / `SuperKey99!`** (created by `bin/rails db:seed`, along with ~30 sample users).

### Lint / test / build
- Lint: `bin/rubocop`
- Tests: `bin/rails db:test:prepare test` (Minitest; billing uses the Pay fake processor, so no external APIs are required). System tests (`bin/rails test:system`) need Chrome and are not required for core validation.
- Full local CI pipeline: `bin/ci` (setup, rubocop, bundler-audit, importmap audit, brakeman, tests, seed replant).

### Optional / credential-gated features
Stripe billing, Google/GitHub OAuth, and real SMTP email require credentials (see `config/credentials.example`, `docs/BILLING.md`). They are not needed to run or test the core product; skip them unless specifically working on those flows.
