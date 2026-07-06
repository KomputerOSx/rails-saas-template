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
- `btn btn-outline` — secondary action (uncolored — see below, this is the "Secondary" button)
- `btn btn-error` — destructive action
- `btn-sm` / `btn-xs` / `btn-lg` — size variants (`btn-sm` most common)
- `btn-square` / `btn-circle` — icon-only buttons

**Rule:** Main function buttons (e.g. "New role", "New permission"), "Back" buttons, and other
navigation buttons all use `btn-sm`. Full-size (`btn` with no size modifier) is not used for these.
Table row actions go smaller still, `btn-xs` (see Tables below).

**Rule:** Buttons keep DaisyUI's semantic classes (`btn`, `btn-primary`, `btn-secondary`, `btn-error`,
`btn-ghost`, `btn-outline`, ...) in views — never hand-roll button styling in a template. The visual
language is re-skinned once, globally, in `app/assets/tailwind/application.css`:

- Solid semantic buttons (`btn-primary`, `btn-error`, etc.) get a subtle same-color tinted border
  (`color-mix(... 40%, transparent)`) instead of DaisyUI's flat solid-color edge — a soft rim rather
  than a hard line.
- The uncolored `btn-outline` (no `btn-primary`/`btn-error`/etc. alongside it) is the app's "Secondary"
  button: a soft translucent `base-100` fill with a faint border, brightening to a solid border +
  `base-content` text on hover. It is not a transparent outline in this app.
- `btn-ghost` is `shadow-none`; fills with a light translucent tint of its color (or `base-content` if
  uncolored) on hover.
- `--radius-field` is `0.5rem` (`rounded-lg`) app-wide, up from DaisyUI's default `0.25rem` — buttons
  and any remaining native DaisyUI field elements pick this up automatically.
- **Press animation:** buttons scale to `96%` instantly on `:active` (`transform: scale(0.96)`), with
  no transition on the transform — it snaps rather than eases. DaisyUI's own `.btn` includes `transform`
  in its default `transition-property`; our override redeclares `transition-property` without
  `transform` (keeping `background-color, border-color, color, box-shadow, opacity` smooth at `100ms`)
  specifically so the press-down doesn't animate.
- `cursor: pointer` is applied globally to any non-disabled `<button>` / `[role="button"]`, not just
  `.btn` — DaisyUI's own `.btn` already sets this, this backstops plain buttons/toggles that skip it.

### Forms & inputs

**Rule:** All text inputs, selects, textareas, and checkboxes use the app's own flat/ringed field
classes — **not** DaisyUI's `input` / `select` / `textarea` / `checkbox` classes. These are defined
in `app/assets/tailwind/application.css` on top of DaisyUI's semantic color tokens (`base-100`,
`base-content`, `base-300`, `primary`, `error`), so they stay correct in both the `dark` and `light`
themes without any hardcoded colors.

| Element | Class |
| --- | --- |
| `<input>` (text/email/password/etc.) | `input-field` |
| `<select>` (single) | `select-field` |
| `<select multiple>` | `select-field` (auto-detected via `:not([multiple])` / `[multiple]` in CSS) |
| `<textarea>` | `textarea-field` |
| `<input type="checkbox">` | `checkbox-field` |
| `<input type="radio">` | `radio-field` |

```erb
<div class="form-control">
  <label class="label"><span class="label-text">Email</span></label>
  <%= f.email_field :email, class: "input-field w-full" %>
</div>
```

- The `form-control` div and `label` / `label-text` classes are still DaisyUI's — only the field
  element itself (`<input>`/`<select>`/`<textarea>`/checkbox) uses the custom classes above.
- No size modifiers (`input-sm`, `select-sm`, etc.) — the field classes are a single fixed size (compact,
  `text-sm`, `px-3 py-2`). Don't reintroduce DaisyUI size classes on top of them.
- **Error state:** append a plain `error` class (not DaisyUI's `input-error`). The `error_class_for(object,
  field, base_class)` helper (`app/helpers/application_helper.rb`) does this automatically — pass it
  the field's base class (e.g. `error_class_for(@user, :email, "input-field w-full")`) and it appends
  `" error"` when the object has errors on that field. Pair with the `field_errors(object, field)`
  helper to render the message below the field.
- Disabled state is handled automatically (`opacity-75`, `cursor-not-allowed`, `bg-base-200`) — just
  set the `disabled` attribute, no extra class needed.
- File inputs aren't used anywhere in the app yet; if one is added, follow `checkbox-field`/`radio-field`'s
  pattern (same tokens, adapt the shape) rather than reaching for DaisyUI's classes.
- **Radio group spanning multiple endpoints:** when each radio option needs to submit to a *different*
  URL (e.g. org settings' role radios — "User" posts to the demote endpoint, "Admin" to the promote
  endpoint), don't split them into separate forms — that breaks native radio mutual-exclusivity (radios
  only group within one `<form>`). Instead use one `form_with` (any option's URL as the default `action`)
  wrapping both radios, with `data-controller="auto-submit"` on the form and, on each radio,
  `data-action="change->auto-submit#submit"` + `data-auto-submit-url-param="<the other endpoints>"`. The
  `auto-submit` Stimulus controller (`app/javascript/controllers/auto_submit_controller.js`) repoints
  `form.action` to the selected radio's URL before calling `requestSubmit()` — one real radio group, no
  visible submit button, backend routes untouched. Reference: `app/views/org/settings/index.html.erb`
  (Edit member modal).

### Badges

**Rule:** Badges keep DaisyUI's semantic classes (`badge`, `badge-primary`, `badge-success`,
`badge-error`, `badge-warning`, `badge-neutral`, `badge-outline`, `badge-ghost`, ...) in views. Like
buttons, the visual language is re-skinned once, globally, in `app/assets/tailwind/application.css` —
never hand-roll badge colors in a template.

- Colored badges (`badge-primary`, `badge-success`, `badge-error`, `badge-warning`, `badge-neutral`,
  `badge-secondary`, `badge-accent`, `badge-info`) are soft pills: a light tinted background
  (`color-mix(... 15%, transparent)`), text in the badge's own color (not white/content-color), and a
  matching tinted border (`color-mix(... 25%, transparent)`) — not DaisyUI's default solid fill.
- `badge-outline` (used for neutral tags like a role's scope) is a soft neutral pill: faint
  `base-content`-tinted background, `base-300` border, `base-content` text.
- `badge-ghost` (used for low-emphasis states like "Off"/"permanent") is left as DaisyUI's default —
  already a muted `base-200` fill, which fits the soft-pill family as-is.
- Already fully rounded (`rounded-full`-equivalent) via the theme's `--radius-selector: 2rem` — no
  extra class needed.
- `badge-sm` / `badge-xs` for size — same sizing rules as elsewhere (small in tables, `xs` for inline
  indicators like the unread-notification count).

### Cards & surfaces

**Rule:** All cards use `card border border-base-300` — no shadow classes (`shadow`, `shadow-*`).

```erb
<div class="card border border-base-300">
  <div class="card-body">
    ...
  </div>
</div>
```

- `card` — DaisyUI base (border-radius, overflow: hidden)
- `border border-base-300` — explicit hard border, always present
- No `shadow` / `shadow-sm` / `shadow-lg` — ever
- `card-body` default padding applies unless the card wraps a flush element (e.g. table → `card-body p-0`)

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
<%# Title + subheader live ABOVE the table %>
<div class="mt-10">
  <h2 class="text-lg font-semibold">Section title</h2>
  <p class="mt-0.5 text-sm text-base-content/60">One-line description.</p>

  <div class="card mt-4 border border-base-300">
    <div class="card-body p-0">
      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead class="text-sm font-semibold text-base-content">
            <tr class="border-b border-base-300">
              <th>Primary column</th>
              <th>Secondary column</th>
              <th class="text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <% collection.each do |item| %>
              <tr class="hover:bg-base-200">
                <td class="font-medium"><%= item.primary_field %></td>
                <td class="text-base-content/60"><%= item.secondary_field %></td>
                <td>
                  <div class="flex justify-end gap-1">
                    <%= button_to path, method: :delete,
                          class: "btn btn-ghost btn-xs btn-square text-error",
                          title: "Remove",
                          data: { controller: "confirm-modal", action: "click->confirm-modal#confirm",
                                  confirm_modal_message_value: "Remove this item?" } do %>
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
  </div>
</div>
```

**Rules:**

**Wrapper:**
- Use `card border border-base-300` — `card` provides border-radius and `overflow: hidden` natively, solving the corner-clipping problem without hacks
- `card-body p-0` removes card padding so the table sits flush to the edges
- `overflow-x-auto` goes inside `card-body`, wrapping `<table>` directly

**Why `card` and not a plain `div` with `rounded-* overflow-hidden`:**
DaisyUI tables use `border-collapse: collapse`, which causes `overflow: hidden` on plain divs to not clip cell backgrounds at the corners in Chrome/WebKit. `card` handles this correctly. Also avoid `rounded-box` — dark theme sets `--radius-box: 0.25rem` (invisible).

**Header row:**
- `bg-base-200` on `<thead>` + `text-sm font-semibold text-base-content` + `border-b border-base-300` on
  the `<tr>`. (Header text style previously `text-base-content/60 text-xs uppercase tracking-wide` —
  replaced to match the flatter, sentence-case style used by buttons/badges/forms.)
- **Corner-bleed guard:** a filled `<thead>` combined with `border-collapse` can leave a hairline square
  corner poking past the card's `border-radius` in Chrome/WebKit, even inside the `card` wrapper's
  `overflow: hidden`. Handled once, globally, in `app/assets/tailwind/application.css`:
  `.table thead tr:first-child th:first-child` / `th:last-child` get `border-top-left/right-radius:
  var(--radius-box)` directly, so the header row's own corners match the card and there's nothing left
  for the parent clip to miss. No per-view markup needed — just use `bg-base-200` on `<thead>` as normal.

**Rows & cells:**
- No zebra striping — tried `table-zebra` (DaisyUI's built-in even-row striping), reverted per
  preference. Rows are otherwise flush against the card background.
- `hover:bg-base-200` on each `<tr>` — **not** a bare `class="hover"`. `hover` alone is not a real
  Tailwind/DaisyUI class (there's no utility named exactly `hover` — it's a variant prefix, e.g.
  `hover:bg-base-200`), so it compiles to nothing and silently did nothing everywhere it was used.
- Primary identifier: `font-medium`
- Secondary/muted data: `text-base-content/60`
- Never put `flex` directly on `<td>` — wrap contents in `<div>`
- Actions column: header `text-right`, cell content `<div class="flex justify-end gap-1">`

**Action buttons:**
- Icon-only: `btn btn-ghost btn-xs btn-square` + `title` attr for tooltip
- Destructive actions: add `text-error`
- Confirmation: wire via `confirm-modal` Stimulus controller (not `data-turbo-confirm`)
- Icons: `person_remove` (remove), `logout` (leave), `cancel` (revoke), `delete` (generic)

**"Edit" modal instead of separate row actions:** when a row has more than one mutating action on the
same record (e.g. change role + remove), collapse them into a single `btn-ghost btn-xs btn-square` edit
button that opens a `data-controller="modal"` dialog, rather than several small buttons/dropdowns
crowded into the row. Reference: `app/views/org/settings/index.html.erb` (Members table) — role is
shown read-only in the table as a `badge badge-outline rounded-none badge-sm` (square, not pill — matches
the table's flat look rather than the rounded badges used for status elsewhere), and the row's only
action is one "Edit member" icon button. Inside that modal:
- Role change: a `radio-field` group (not a dropdown, not separate buttons) auto-submitting on change —
  see the "Radio group spanning multiple endpoints" note under Forms & inputs above, since role posts to
  two different endpoints (promote/demote) from what's otherwise one radio group.
- Destructive action (remove): its own `btn-error btn-outline btn-sm w-full` button at the bottom, still
  wired to `confirm-modal`. The shared `#confirm-modal` dialog (`app/views/shared/_confirm_modal.html.erb`)
  is a single global `<dialog>`, so it layers on top of an already-open edit modal without any special
  handling — no need to build a bespoke nested-modal mechanism.
- A user's own row keeps its distinct "Leave organization" icon button (unchanged) rather than going
  through the edit modal — you can't self-edit a role, only leave.

**Sortable headers:** use the `sort_link` helper — `sort_link "Label", "column", current_sort: @sort, current_dir: @direction`

**Inline role/status:** DaisyUI `dropdown` — current value as clickable text + `unfold_more` chevron; each option is a `button_to` form

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
- ✅ Do use `card border border-base-300` for all card components.
- ❌ Don't add shadow classes (`shadow`, `shadow-sm`, `shadow-lg`, etc.) to cards.
