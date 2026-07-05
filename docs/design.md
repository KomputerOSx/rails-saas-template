# Design System

Living reference for how this app looks and feels. Keep this in sync with reality — if you change a
convention in code, update it here in the same PR.

## Stack

- **CSS framework:** Tailwind CSS (via `tailwindcss-rails`, config at `config/tailwind.config.js`)
- **Component library:** [DaisyUI](https://daisyui.com)
- **Icons:** Material Symbols (Outlined) — `<span class="material-symbols-outlined">icon_name</span>`
- **Other UI libs:** Shoelace (`<sl-*>` web components), Tom Select (multi-selects), Air Datepicker,
  Photoswipe (image lightboxes)
- **Rendering:** Server-rendered ERB + Turbo/Stimulus, no SPA framework

## Theming

- Default/only theme today: DaisyUI `dark`, set via `data-theme="dark"` on `<html>` in every layout.
- Theme is persisted client-side in `localStorage.getItem("theme")` and applied before paint via an
  inline `<script nonce>` in `<head>` to avoid a flash of unstyled theme.
- Theme toggle button pattern: `data-theme-target="icon"` swaps the `light_mode` / `dark_mode`
  material symbol.
- <!-- TODO: fill in — are we adding a light theme? Custom DaisyUI theme (brand colors) or stock
  "dark"/"light"? If custom, define the palette below. -->

### Color palette

<!-- TODO: fill in. If using stock DaisyUI dark theme, list which semantic tokens we actually use.
     If custom, give hex values per token. -->

| Token             | Usage                                  | Value |
| ------------------ | --------------------------------------- | ----- |
| `base-100`         | Page/card background                    |       |
| `base-200`         | Sunken surfaces (sidebars, subtle panels) |     |
| `base-300`         | Borders, dividers                       |       |
| `base-content`     | Default text color                      |       |
| `primary`          | Primary actions, links, brand accent    |       |
| `secondary`        | —                                       |       |
| `accent`           | —                                       |       |
| `neutral`          | —                                       |       |
| `success` / `error` / `warning` / `info` | Status states     |       |

## Layouts

Each layout wraps a distinct part of the app in `app/views/layouts/`:

| Layout | File | Used for |
| --- | --- | --- |
| Application | `application.html.erb` | Main authenticated app shell — sidebar + navbar + content |
| Auth | `auth.html.erb` | Sign in / sign up / password reset |
| Onboarding | `onboarding.html.erb` | Post-signup onboarding flow |
| Landing | `landing.html.erb` | Public marketing/landing pages |

<!-- TODO: fill in — any layout-specific rules (max-width, when to use which layout, etc.) -->

### App shell structure (`application.html.erb`)

- `drawer lg:drawer-open` (DaisyUI drawer) — collapsible sidebar on mobile, always-open on `lg+`
- Sticky, blurred header: `sticky top-0 z-50 border-b border-base-300 bg-base-100/95 backdrop-blur`
- Content column: `main` capped at `max-w-7xl`, padding `px-4 py-8 lg:px-8`
- Toasts + flash messages render at the top of `main` on every page (`shared/toast_container`,
  `shared/flash`)

## Layout & spacing conventions

<!-- TODO: fill in — standard page padding, section spacing, grid/breakpoint conventions,
     container widths for non-app pages (e.g. auth, landing). -->

## Typography

<!-- TODO: fill in — font family (currently system default, no custom font loaded), heading
     scale/weights, body text size, any prose/markdown styling conventions. -->

## Components

Prefer existing DaisyUI component classes over custom CSS. Document conventions here as they solidify
(e.g. "always use `btn-sm` in tables", "destructive actions are always `btn-error` + confirm modal").

### Buttons

Observed usage across the app today:

- `btn btn-primary` — primary/default action
- `btn btn-ghost` — low-emphasis / toolbar actions
- `btn btn-outline` — secondary action
- `btn btn-error` — destructive action
- `btn-sm` / `btn-xs` / `btn-lg` — size variants (`btn-sm` most common)
- `btn-square` / `btn-circle` — icon-only buttons

<!-- TODO: fill in — house rules for when to use each variant, icon+label spacing convention, etc. -->

### Forms & inputs

<!-- TODO: fill in — input/select/textarea conventions, validation/error state styling,
     Tom Select usage rules, label placement. -->

### Cards & surfaces

<!-- TODO: fill in — standard card padding/border/shadow, when to use base-100 vs base-200,
     nesting rules. -->

### Navigation (navbar & sidebar)

- Navbar: `app/views/shared/_navbar.html.erb`
- Sidebar: `app/views/shared/_sidebar.html.erb`

<!-- TODO: fill in — active-state styling, icon usage, collapsed/mobile behavior beyond the
     DaisyUI drawer defaults. -->

### Notifications (toasts & flash)

- `shared/_toast_container.html.erb` and `shared/_flash.html.erb` rendered once in the app layout.

<!-- TODO: fill in — toast variants/colors per flash type, auto-dismiss timing, position. -->

### Modals & dialogs

<!-- TODO: fill in — DaisyUI modal vs Shoelace dialog usage, when each is used. -->

### Tables

Standard table pattern. Reference: `app/views/org/settings/index.html.erb` (Members table).

**Structure:**
```erb
<%# Title + subheader live ABOVE the table, not inside a card %>
<div class="mt-10">
  <h2 class="text-lg font-semibold">Section title</h2>
  <p class="mt-0.5 text-sm text-base-content/60">One-line description.</p>

  <div class="mt-4 overflow-x-auto">
    <table class="table table-sm">
      <thead class="bg-base-200 text-base-content/70 text-xs uppercase tracking-wide">
        <tr>
          <th>Primary column</th>
          <th>Secondary column</th>
          <th class="text-right">Actions</th>
        </tr>
      </thead>
      <tbody>
        <% collection.each do |item| %>
          <tr class="hover">
            <td class="font-medium"><%= item.primary_field %></td>
            <td class="text-base-content/60"><%= item.secondary_field %></td>
            <td>
              <div class="flex justify-end gap-1">
                <%# icon-only action buttons %>
                <%= button_to path, method: :delete, class: "btn btn-ghost btn-xs btn-square text-error", title: "Remove" do %>
                  <span class="material-symbols-outlined" style="font-size:18px">delete</span>
                <% end %>
              </div>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

**Rules:**
- **No card wrapper** around tables — tables stand alone
- **Title + subheader** sit above the table div, never inside it
- `overflow-x-auto` wraps the `<table>` directly (not the whole section)
- Use `table table-sm` — `table-sm` is default density
- `<thead>` always has `bg-base-200 text-base-content/70 text-xs uppercase tracking-wide` for visual separation from body
- `hover` on each `<tr>` for hover state
- Primary identifier cell: `font-medium`
- Muted/secondary data: `text-base-content/60`
- Never put `flex` directly on `<td>` — wrap in `<div>`
- Actions column header: `text-right`; actions cell: `<div class="flex justify-end gap-1">`
- **Action buttons are icon-only**: `btn btn-ghost btn-xs btn-square` + `title` attr for tooltip
  - Destructive: add `text-error`
  - Icons: `person_remove` (remove member), `logout` (leave), `cancel` (revoke), `delete` (generic delete)
- **Inline role/status changes** use a DaisyUI `dropdown` — display current value as clickable text with `unfold_more` chevron; dropdown lists all valid transitions as `button_to` forms

**Empty state:** render `<p class="mt-4 text-sm text-base-content/60">No items.</p>` in place of the table.

### Layout — centering

`<main>` in `application.html.erb` uses `mx-auto` to center content within the flex column. Each page's top-level wrapper controls its own max-width (e.g. `max-w-4xl` for settings pages).

### Empty states

<!-- TODO: fill in. -->

## Third-party component usage

- **Shoelace** (`<sl-*>`): <!-- TODO: which components, and why Shoelace instead of DaisyUI here
  (e.g. color-picker) -->
- **Tom Select**: <!-- TODO: which fields/forms use it -->
- **Air Datepicker**: <!-- TODO: which fields/forms use it -->
- **Photoswipe**: <!-- TODO: where image galleries/lightboxes appear -->

## Responsive & accessibility rules

<!-- TODO: fill in — breakpoint strategy (mobile-first?), min touch target sizes, contrast
     requirements, focus-visible conventions, keyboard nav expectations. -->

## Voice & content

<!-- TODO: fill in — tone (formal/casual), capitalization rules for buttons/headings (Title Case
     vs sentence case), terminology glossary (e.g. "Login" not "Sign in" — see terminology
     refactor commit 4289b7b). -->

## Do / Don't

<!-- TODO: fill in as conventions get established. Examples of the format: -->

- ✅ Do use DaisyUI semantic color tokens (`bg-base-200`, `text-primary`) instead of raw Tailwind
  colors (`bg-gray-100`, `text-blue-500`), so theme changes propagate everywhere.
- ❌ Don't hardcode hex colors in views or component partials.
