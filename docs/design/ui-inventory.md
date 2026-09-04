# UI inventory — what the AGO interfaces actually are today

**Purpose.** A factual description of every screen and view state that exists in the two user
interfaces, written so a designer who has never opened the codebase can reason about them. It is
one half of the input to a deliberate redesign; the other half — the *intended* flows — is written
separately by the author.

**This document does not recommend anything.** Where a screen has no empty state, that is recorded
as a fact ("this screen has no empty state"), not as a suggestion. Nothing here says "should".

**Sources.** Every claim comes from a file read at these commits. Nothing was inferred from a
component name, and nothing was run.

| Repository | Commit read |
|---|---|
| `ago-console` | `1eba8d39426b6361f0071be15952ad768a36cf8a` (`origin/main`) |
| `ago-widget` | `5e093048151c5f0421c1740393591d0095f94a5d` (`origin/main`) |
| `ago-root` (this doc's base) | `9792aeefc979b2f0569e1ddbbfa2853415fd9dee` (`origin/main`) |

Where a screen was not fully established, section 15 says so and names what was looked at. The
backlog in `docs/backlog/` is cited only where marked **planned**; the code is the source of truth
for what exists.

---

## 0. How to read this

- **Routes** are literal `react-router` paths from `ago-console/src/App.tsx`.
- **"Who reaches it"** names one of five roles. The console never gates a *route* on a permission —
  `RequireAuth` only asks "is there an OIDC session"; each page checks its own permission after
  mounting and renders a refusal in place of its content. `App.tsx`'s own doc comment states this
  deliberately: "authenticated is a route concern, authorized is a page concern".
- **States** list every branch the component actually renders, including the ones it does not have.
- Class names (`.ago-…`) are given where a designer would need them to match a screenshot to a rule.

### The five roles, as the code expresses them

There is no role model in the console. There is a flat permission list returned by
`GET /api/v1/operators/me` (`src/api/operatorsApi.ts`, consumed by `src/auth/PermissionsProvider.tsx`),
plus one Keycloak realm role probed separately.

| Role in the brief | How the code recognises it |
|---|---|
| Visitor | Never signs in. Widget only; no console route. |
| Chat operator | Any authenticated identity with an `operators` row. Baseline: holds none of the gating permissions below. |
| Calendar operator | Holds `calendar:configure`. |
| Tenant admin / owner | Holds `site:configure` (and possibly `site:erase`). |
| Platform owner | A Keycloak realm role. The console never reads it from a token — `useOwnerEligibility` (`src/auth/useOwnerEligibility.ts`) *probes* `GET /api/v1/owner/sites` and treats the server's answer as the flag. |

**The complete permission vocabulary the console checks** (every `hasPermission("…")` call site):

`site:configure` · `site:erase` · `calendar:configure` · `conversation:read` · `conversation:send` ·
`conversation:close` · `conversation:tag` · `conversation:note_write` · `channel_identity:unlink` ·
`conversation:erase` · `attachment:delete`

A twelfth, `site:manage-operators`, exists server-side and is named in a comment in
`src/api/billingApi.ts` — the console never checks it and has no screen behind it (section 14).

---

## 1. The console shell — the frame every signed-in screen sits in

Files: `src/shell/AppShell.tsx`, `src/shell/shell.css`, `src/shell/OperatorShell.tsx`,
`src/shell/consoleNav.ts`.

There are three shell shapes:

1. **`AppShell`** — the full frame. Two stacked header rows, an optional full-bleed demo notice, and
   a `<main>`. Used by every signed-in screen.
2. **`CenteredShell`** — brand row only, content vertically and horizontally centred. Used by the
   sign-in redirect spinner (`RequireAuth`) and `/callback`.
3. **`AppShell` with no `nav` and no `identity`** — used by `/signup`.

### Header, row 1 ("who you are")

Left: a hamburger button (`.ago-shell__menu-button`, hidden by CSS above `40rem`), then the brand —
a 2rem lilac square with the letter `A`, the wordmark `AGO` in Unbounded, and a small uppercase
tagline underneath.

The tagline is variable and this is the only place the product names itself:

| Tagline | When |
|---|---|
| `Operator console` | default |
| `Client console` | on `/admin`, `/settings/widget`, `/settings/install`, `/settings/auto-reply`, `/settings/billing` only — an explicit `useMatch` list in `OperatorShell.tsx` |
| `Platform owner console` | on `/owner` |

Right: the identity cluster — an optional tenancy `Select` (only when the identity has more than one
tenancy), the operator's display name, an optional `site <first 8 hex>` mono badge (only when there
is *no* tenancy switcher), a theme `Select` (Match system / Light / Dark), and a small secondary
**Sign out** button.

### Header, row 2 ("where you can go")

A single horizontal strip of `NavLink`s, `flex-wrap: nowrap; overflow-x: auto`. It is hidden below
`40rem` and replaced by the hamburger + drawer. Order and gating come from
`buildTenantNavItems()` in `src/shell/consoleNav.ts`:

| # | Label | Route | Gate |
|---|---|---|---|
| 1 | Conversations | `/` | none (always shown) |
| 2 | All conversations | `/admin` | `site:configure` |
| 3 | Search | `/search` | `site:configure` |
| 4 | Analytics | `/analytics` | `site:configure` |
| 5 | Conversion | `/analytics/conversion` | `site:configure` |
| 6 | Tag report | `/analytics/tags` | `site:configure` |
| 7 | Booking flow | `/analytics/booking-flow` | `site:configure` |
| 8 | Install widget | `/settings/install` | `site:configure` |
| 9 | Widget appearance | `/settings/widget` | `site:configure` |
| 10 | AI FAQ assistant | `/settings/faq` | `site:configure` |
| 11 | Offline auto-reply | `/settings/auto-reply` | `site:configure` |
| 12 | Canned responses | `/settings/canned-responses` | `site:configure` |
| 13 | Tags | `/settings/tags` | `site:configure` |
| 14 | Billing | `/settings/billing` | `site:configure` |
| 15 | Delete account | `/settings/delete-account` | `site:erase` |
| 16 | Queue | `/calendar` | `calendar:configure` |
| 17 | Setup | `/calendar/setup` | `calendar:configure` |
| 18 | Workers | `/calendar/workers` | `calendar:configure` |
| 19 | Availability | `/calendar/availability` | `calendar:configure` |
| 20 | Contacts | `/calendar/contacts` | `calendar:configure` |
| 21 | Platform sites | `/owner` | `useOwnerEligibility() === "eligible"` (appended in `OperatorShell.tsx`, not in `consoleNav.ts`) |

**This is a flat list of up to 21 items in one horizontal strip.** There is no grouping, no section
heading, no submenu, and no visual break between "chat", "settings", "calendar" and "platform".
Two labels are ambiguous out of context — "Queue" (calendar) sits nine items after "Conversations"
(the chat queue), and "Setup"/"Install widget" are both first-run installation screens for two
different products.

The active item is marked three ways at once (colour, weight 800, and a 2px underline that grows
from the left on hover), plus `aria-current="page"`.

### The demo notice

`.ago-demo-notice` — a full-bleed strip below the header, painted in the *danger* palette
(`--ago-danger` on `--ago-danger-tint`), rendered only when `VITE_PUBLIC_DEMO === "true"`. Not
dismissible. Two texts: a "shared login, do not type anything real" version for ordinary operators
and a longer platform-owner version. It is inside the same `position: sticky` wrapper as the header,
so header + notice pin together as one unit.

### The mobile drawer

Below `40rem` the nav row is `display: none` and the hamburger appears. The drawer is a real native
`<dialog>` opened with `showModal()` (`src/components/Dialog.tsx`, `variant="drawer"`), fixed to the
left edge, `width: min(20rem, 85vw)`, full height, sliding in with a transform. It renders the *same*
`nav` array as the bar — one data source, two renderers. Focus trapping, Escape-to-close, backdrop
click and focus restoration to the hamburger are the browser's, and are covered by
`ux-gate/mobileNavDrawer.spec.ts`.

### The eleven components

`adr/0030` closes the shared set at eleven hand-rolled components; there is no component library.
`src/components/`: `Alert`, `Badge`, `Button`, `Dialog`, `Field`, `Input`, `Panel`, `Select`,
`Spinner` (which also exports `Skeleton`), `Table`, `Textarea`. Everything else is a class name in
one of five stylesheets (`design/tokens.css`, `design/base.css`, `components/components.css`,
`index.css`, `shell/shell.css`, `workspace/workspace.css`).

Notable component limits, from their prop types:

- **`Table`** takes `caption`, `columns`, `rows`, `rowKey`. There is no sorting, no pagination, no
  row selection, no column visibility, no sticky header, no per-row expansion. Columns have exactly
  one option: `align: "start" | "end"`. Every table in the product is this component.
- **`Alert`** has four tones (`danger`, `success`, `info`, plus an untoned default) and an optional
  `action` slot. It is not dismissible.
- **`Dialog`** has `modal` and `drawer` variants and a `footer` slot. No size variants.
- **`Field`** is a render-prop wrapper giving a label, an optional description, an optional error and
  an optional `adornment` (used once, for the widget colour swatch).
- **`Panel`** has `title`, `description`, `actions`, `quiet`. No collapse.
- **`Spinner`/`Skeleton`** are the only two loading treatments. `Skeleton` takes a line count.

### The four state idioms

The console has a named vocabulary for states (`components.css`, "States" section):

| State | Treatment |
|---|---|
| Loading | `<Spinner>` (a ring plus a label) or `<Skeleton lines={n}>` (shimmering bars) |
| Empty | `<p className="ago-empty">` — a centred sentence in a dashed-border box |
| Error | `<Alert tone="danger">` |
| Success | `<Alert tone="success">` |
| Permission denied | `<PageHead title=…/>` with **no description**, an `Alert tone="danger"`, and a `<Link to="/">Back to queue</Link>` |
| Not configured | `<Alert tone="info">` (calendar and FAQ screens only) |

There is no `EmptyState` *component* — `NoConversationSelected` has its own bespoke
`.ago-empty-state` block (glyph + title + body, centred) which nothing else uses.

### Layout containers

- `--ago-shell-max: 1180px`, `--ago-content-max: 68rem` (1088px), `--ago-gutter: 1.25rem`.
- `OperatorShell` passes `wide` unconditionally, so **every** signed-in screen uses the 1180px cap,
  never the 1088px reading measure. `/signup`, `/onboarding` and `/owner` render `AppShell`
  themselves; `/owner` also passes `wide`, `/signup` and `/onboarding` do not.
- `fixed` (viewport-height, internal scrolling) is passed only for `/` and `/conversations/:id`.

---

## 2. Pre-session and account screens

### 2.1 `/callback` — "Completing sign-in"

**Who.** Anyone returning from Keycloak.
**For.** Finishing the OIDC redirect and deciding where to land.
**On it.** `CenteredShell` + a `Spinner` labelled "Completing sign-in…". Nothing else.
**States.**
- *Working*: the spinner. This is the whole screen in the normal case.
- *Sign-in failed*: `Alert tone="danger"` titled "Sign-in failed" with the raw error message.
- *Signed in but the account lookup failed*: a distinct alert, "Signed in, but couldn't load your
  account", whose body names the failing endpoint (`GET /api/v1/operators/me`) and its error text.
  This is written to a reader who can act on it — it explicitly says "this is not a problem with
  your Keycloak sign-in".
- A *replayed* callback (browser back button) silently redirects to `/`.

**In / out.** In: Keycloak only. Out (all `replace`): `/` if the identity has an operator row;
`/owner` if it has none but is the platform owner; `/onboarding` otherwise. On failure there is
**no link out at all** — the two error states are dead ends whose only instruction is "reload".

**Language.** Hardcoded English.

### 2.2 `/signup` — "Sign up for AGO Chat"

**Who.** A visitor with no session at all. No guard.
**For.** Getting to Keycloak's own registration page.
**On it.** A `PageHead` ("Sign up for AGO Chat" + one explanatory sentence saying the email and
password are chosen on Keycloak's page) and one primary **Sign up** button. That is the entire
screen — no form, no fields, no marketing.
**States.** Idle · redirecting (button reads "Opening sign-up…", disabled) · error
(`Alert tone="danger"` with "Could not open the sign-up page").
**In / out.** **Nothing in the console links here.** `SignupPage.tsx`'s own doc comment says so
explicitly and explains why: `RequireAuth` redirects an unauthenticated visitor straight to
Keycloak's login page, so there is no console-rendered page a "Sign up" link could live on. The
route exists to be linked from outside (a marketing page). Out: Keycloak.
**Language.** Hardcoded English.

### 2.3 `/onboarding` — "Finish setting up your site"

**Who.** An authenticated identity with **no** `operators` row. Guarded by `RequireAuth` only —
deliberately not wrapped in `PermissionsProvider` or the realtime provider, because the token has no
site claims yet.
**For.** Creating the tenant's site so the rest of the console has something to point at.
**On it.** `PageHead` + a `Panel` containing a two-field form:
- **Site display name** (text, required, non-empty)
- **Embed origin** (text, must parse as a URL with `http:`/`https:`; description says "scheme, host
  and port only — no path", placeholder `https://shop.example.com`)
- primary button **Finish setup** / "Setting up…"

**States.** Idle · submitting · client validation error (`Alert tone="danger"`, one message at a
time) · server error. If the server answers `Site.AlreadyRegistered` the page silently navigates to
`/` — the user sees a flash, not a message.
**A fifth state**: if the identity is *also* the platform owner, an `Alert tone="info"` appears above
the form ("You are signed in as the platform owner") with an action link to `/owner`, warning in
plain words that registering additionally makes this account an operator of a new site and "nothing
in this product can take it back afterwards".
**In / out.** In: `/callback` only. Out: `/` on success, `/owner` via that alert. The header carries
the identity cluster and Sign out but **no nav** (there is no `siteId` yet).
**Language.** Hardcoded English, including validation messages.

---

## 3. The operator workspace

Route: `/` and `/conversations/:conversationId`. Both render inside one layout route,
`src/workspace/WorkspaceLayout.tsx`, which owns the queue data, the realtime connection banner, the
conversation list, keyboard shortcuts and the alert settings. Styling: `src/workspace/workspace.css`.

### 3.0 The frame

A CSS grid with three named areas, `rail main aside`, at fixed track widths
`21rem minmax(0, 1fr) 18rem`. The shell is `height: 100dvh` here (and only here), so each region
scrolls internally rather than the page scrolling.

Two breakpoints, both in `rem`:
- **≤ 74rem (~1180px)** — the aside loses its column and becomes a strip *above* the thread; the grid
  becomes `19rem minmax(0,1fr)` with two rows. The aside's fact list re-flows into an auto-fit grid,
  and its closing note is `display: none`.
- **≤ 52.5rem (~840px)** — one column. The shell stops being viewport-height and the page scrolls
  normally. The rail (conversation list) is hidden *whenever a conversation is open*, and a
  `← Conversations` back link appears in the conversation header. The thread gets
  `max-height: 60vh` so the composer stays reachable.
- **≤ 40rem** — additionally, the composer's action row stacks below the textarea. The file's own
  comment records the measurement that forced this: at a 375px viewport the textarea was 28.5px wide,
  wrapping text one character per line.

The file states its own posture: *"This is a laptop tool that degrades honestly, not a mobile app:
the goal at the narrow end is 'usable and not broken', not 'designed for a phone'."*

### 3.1 The rail — conversation list

**Who.** Every operator. Ungated.
**For.** Seeing what is assigned to you and what is waiting.
**On it**, top to bottom:
1. A row with the uppercase label **Conversations** and a `ConnectionStateBadge` (a dot badge whose
   label is one of Live / Connecting… / Reconnecting… / Server restarting / Offline; the full
   explanatory sentence is in its `title` attribute only).
2. Two small ghost buttons: **Alerts** and **Shortcuts**.
3. If the link is unhealthy, an `Alert tone="danger"` carrying the badge's label and detail.
4. If the site has any tags, a bare `Select` filtering the queue by tag ("All tags" + each tag).
5. Any queue-load error, then any transient announcement ("A new conversation was assigned to you.",
   auto-clearing after 20s).
6. The scrolling list itself, in two sections.

**Section "Assigned to me"** — note: *"Live — a new assignment appears without a refresh."* Each row
is a whole-row `NavLink`: a brand mono badge with the visitor id's **first 8 hex characters**, an
optional accent "New" badge, an optional danger unread-count badge, and a second line reading
`Open 14m` (elapsed, ticking every 10s; the absolute timestamp is in the `title`).

**Section "Waiting"** — note: *"Read-only — conversations are assigned automatically, never claimed
here. Refreshed every 15 seconds."* Rows are `<li>` with `.ago-list__row--static`: sunken surface,
dashed border, default cursor, no hover, no link. A neutral mono badge with 8 hex characters and
`Waiting 4m`. **There is no claim action anywhere in the product.**

**States.** Loading = a `Skeleton` per section (3 lines / 2 lines). Empty = per section, `.ago-empty`
("Nothing assigned yet. New conversations arrive here automatically." / "Nothing waiting."). Error =
one `Alert` above the list. No permission-denied state — the rail is ungated.

The queue polls every 15s and also refreshes on a realtime assignment event. The document title
carries the unread count.

### 3.2 `/` — no conversation selected

**On it.** `.ago-workspace__main--empty` spans the `main` and `aside` columns. A centred block: a
3rem tinted rounded square containing the glyph **⌘**, an `<h2>` "Pick a conversation", and a
paragraph: "Choose one of the conversations assigned to you on the left. New ones are assigned to
you automatically as visitors start chatting — nothing here needs claiming."
**States.** One. It renders identically whether the queue is empty, loading or full.
**In / out.** The default route. Out: a rail row, or the nav.

### 3.3 `/conversations/:conversationId` — the open conversation

**Who.** Any operator the conversation is assigned to. There is no route-level gate; the *hub*
refuses a join the operator may not have.
**For.** Reading and answering one visitor.

**Header** (`.ago-workspace__main-head`): a `← Conversations` link (visible only below 52.5rem), an
`<h2>` reading `Conversation with <first 8 hex>` — or the bare fallback "Conversation" when the
summary is not in the queue — and, pushed to the far end, a small ghost **Close conversation** button
(rendered only with `conversation:close`).

**Thread** (`src/workspace/Thread.tsx`, `.ago-thread-scroll`):
- Optional "Load older messages" button at the top; "Loading…" while fetching.
- Day separators — a rule with `Today` / `Yesterday` / a formatted day sitting in it.
- Message bubbles, two-tone by author: operator right-aligned on `--ago-brand-tint`, visitor
  left-aligned on white with a hairline. The first message of a run carries the author in words
  above it ("Visitor" / "Operator" / "System") and squares off the corner pointing at its own side.
  `max-width: min(46rem, 82%)` (92% below 52.5rem).
- Each bubble: body (`white-space: pre-wrap`), any attachment, then a meta line with the clock time
  as a `<time>`. The sequence number is visible only in dev builds; in production it survives in the
  bubble's `title` alongside the absolute timestamp.
- A search-arrival highlight: a 2.4s brand ring animation on the bubble matching `?at=<sequence>`.

**Attachment sub-states inside a bubble**: loading (`Spinner`), deleted (a meta line "Attachment
deleted"), unavailable (a danger badge with `role="alert"`), a thumbnail link, or a text
"Download attachment (mime/type)" link. With `attachment:delete`, a small danger **Delete
attachment** button sits beside it.

**Composer** (`src/workspace/Composer.tsx`):
- One auto-growing `Textarea` (min 2.75rem, max 12.5rem) with placeholder "Write a reply — Enter to
  send, Shift+Enter for a new line".
- Actions: **Attach** (ghost, opens a hidden native file input), **Suggest a reply** (ghost, AI
  draft; reads "Generating a suggestion…" while working), **Send** (primary).
- A hint line under it: "Enter sends · Shift+Enter starts a new line · Escape clears · drop or paste
  a file to attach", plus "· Type / to insert a canned response" when the site has any.
- Typing `/` opens an inline canned-response picker — an in-flow (not floating) bordered box with a
  scrolling `role="listbox"`, keyboard `↑↓/Enter/Esc`, and the hint "↑↓ to choose · Enter to insert ·
  Esc to cancel". Empty match state: "No canned response matches."
- The whole composer is the drag-and-drop target; while dragging it turns dashed and brand-tinted.
- Upload progress is an `Alert tone="info"` reading `Uploading <name> — 42%`. A staged attachment is
  a brand badge "Attached" + the file name + a ghost **Remove**.

**States of the whole screen.**
- *Hub not connected*: a `role="status"` line, "Waiting for the operator hub before this thread can
  load or send." The thread and composer still render.
- *Join failed*: `Alert tone="danger"` with a long recovery sentence, **and the composer is removed
  entirely** — the screen becomes a header, an alert and an empty thread.
- *Closed*: the Close button disappears and the composer is replaced by an `Alert tone="info"`,
  "This conversation is closed" / "Your capacity has been released… The transcript above stays
  readable."
- *Send failed or unconfirmed*: an `Alert tone="danger"` above the composer quoting the failed body,
  with a **Retry** action button.
- *Locating a searched message*: a spinner at the top of the thread.
- **No empty state for the thread.** A conversation with zero messages renders an empty `<ol>` and
  nothing else.
- **No per-message delivery state.** Operator bubbles show a timestamp; there is no sent / delivered
  / read indicator anywhere.

**Closing** is a two-step: the ghost button opens a `Dialog` ("Close this conversation?") whose body
explains the visitor's chat ends, it cannot be reopened, and capacity is freed. Six distinct failure
messages are mapped by `closeOutcome.ts` (network, already closed, concurrency conflict, not found,
reassigned, no permission) and shown inside the dialog; retryable failures relabel the confirm button
to "Try again".

**Keyboard shortcuts** (`useShortcuts`, listed in a dialog): next / previous assigned conversation,
focus composer, close the open thread, show help. They are suppressed while a text field has focus.

**In / out.** In: a rail row, a search result, the `?at=` deep link, the next/previous shortcut, a
desktop notification click. Out: the rail, the back link (mobile only), `Escape`'s close-thread
shortcut.

### 3.4 The visitor aside — six stacked panels

`src/workspace/VisitorPanel.tsx`, in the 18rem `aside` column. Every sub-panel is gated on
`conversation:read` and renders **nothing at all** (`null`) without it — so an operator lacking that
permission sees the facts block and the closing note with a silent gap where five sections would be.

1. **Header block.** Title "Visitor", a presence badge (Online / Offline / Presence unknown — polled
   every 10s), and a state badge (Waiting / Assigned / Closed). Then a `<dl>` of four facts: full
   visitor id, conversation start (absolute + elapsed), site id, conversation id — all in mono,
   wrapped rather than truncated so they can be copied whole.
2. **Previous conversations.** A list of the visitor's earlier conversations: state badge,
   `Started <date> — Closed <date>` or "Still open", and a one-line ellipsised preview. Rows are
   `<button>`s that open a `Dialog` rendering the historical thread read-only. States: skeleton /
   danger alert / `.ago-empty` "No prior conversations with this visitor yet."
3. **Tags.** Applied tags as badges; an AI-applied tag is accent-toned with an "AI" marker. Each
   badge carries a small inline `×` (with `conversation:tag`). Below, a `Select` + **Apply** button.
   States: skeleton / alert / `.ago-empty` "No tags applied."
4. **Notes.** Title, then the standing note "The visitor never sees these." A list of timestamped
   note rows (static, sunken, dashed). With `conversation:note_write`, a `Textarea` + **Add note**.
   States: skeleton / alert / `.ago-empty` "No notes yet."
5. **Outcome.** A single badge (Not recorded / Converted / Not converted / Follow-up needed) and,
   with `conversation:close`, three buttons to set it — the current one is `primary` and disabled.
   A closing note: "Recorded by the operator - not a sale AGO Chat has independently verified."
6. **Linked channels.** Rows of `kind` badge + mono address + Preferred badge, with Prefer / Clear
   and Unlink buttons behind separate permissions. Below, a `Select` of linkable channel kinds and a
   **Generate code** button; the generated code is shown in an `Alert tone="success"` as plain text.
7. **Unverified contact details.** Caption "Recorded by an operator - never used to contact the
   visitor automatically." Rows of accent `kind` badge + value + **Delete**. Below, a `Select` of
   kinds + a free-text input + **Record**.

The panel closes with a standing note explaining that the current page and referrer are not collected
yet, and that earlier conversations appear when the visitor is recognised on MAX / Telegram / SMS.
That note is `display: none` below 74rem.

### 3.5 Two dialogs off the rail

**Shortcuts** — a `<dl>` of `<kbd>` + description rows, an intro paragraph and a closing hint line.
**Alerts** — two checkbox switches, "Desktop notifications" and "Sound", each with a sub-label.
Intro: "Both are off until you turn them on, and neither fires for the conversation you already have
open on a visible tab." If the browser has denied notifications, the desktop switch is replaced by a
danger-tinted paragraph explaining that the console cannot ask again and the setting must be changed
in browser site settings; an unsupported browser gets its own variant.

---

## 4. Supervision screens

### 4.1 `/admin` — "All conversations"

**Who.** `site:configure`.
**For.** Seeing every conversation on the site, not just your own.
**On it.** `PageHead` with the description "Every conversation for this site (newest first,
read-only, refreshed every 15 seconds)." Optionally a bare tag-filter `Select` (only when the site
has tags). Then one `Table` with five or six columns:

| Column | Content |
|---|---|
| Visitor | neutral mono badge, **first 8 hex** of the visitor id |
| State | badge: Waiting (brand) / Assigned (success) / Closed (neutral) |
| Assigned operator | mono, **first 8 hex** of the operator id, or the meta word "Unassigned" |
| Started | absolute timestamp in the reader's zone |
| Unread | integer, right-aligned |
| Actions | only with `conversation:erase`: a ghost **Erase** button |

**Rows are not links.** There is no way to open a conversation from this table — see section 13.

**States.** Checking permissions (`Spinner`) · permission denied (`PageHead` with no description,
danger alert, "Back to queue" link) · loading (`Skeleton lines={4}`) · empty (`.ago-empty`,
"No conversations yet.") · error (`Alert`) · a success alert after an erase ("The conversation has
been erased."). Erasing is a two-step confirm dialog followed by a polling `Spinner` in the row.

### 4.2 `/search` — "Search"

**Who.** `site:configure`.
**For.** Finding a conversation by what was said in it.
**On it.** `PageHead` + description ("Full-text search across every conversation on this site.
Results are newest first - this is plain word matching, not a relevance ranking."), then a standing
note that only the shown date range is searched and older conversations "may still exist but [are]
not reachable from here". Then a horizontal form (`.ago-search-form`, wrapping flex, bottom-aligned):
a **Search phrase** input (`flex: 1; min-width: 16rem`), **From (optional)** and **To (optional)**
native date inputs, and a primary **Search** button.

Results are a vertical list, not a table. Each row: a state badge, the author kind in words, the
date, then the **full matched message body** (`white-space: pre-wrap`, never a snippet). A row for an
`Assigned` conversation is a link to `/conversations/:id?at=<sequence>` with the note "Open →". A
`Waiting` row is static with "Unclaimed — assign it from the queue to open it." A `Closed` row is
static with "Closed — a closed conversation cannot be reopened as a live thread."

Below, a "Load more" button when there is another page.

**States.** Checking permissions · permission denied · **initial (nothing searched yet): the form and
nothing else — no prompt, no recent searches, no empty illustration** · searching (`Skeleton`) ·
no matches (`.ago-empty`, "No matches in this range.") · results · loading-more · error, with three
distinct messages (forbidden / "Enter a search phrase." / generic).

---

## 5. Reports

Four sibling routes, all gated on `site:configure`, all built from the same parts: a `PageHead`, an
optional preset row, a `.ago-search-form` date range, a "Showing 1 Sep 2026 – 30 Sep 2026" meta line,
and one or more `Table`s. **None of them contains a chart, a sparkline, a trend arrow, or any
graphical element.** Every number is a table cell.

### 5.1 `/analytics` — "Analytics"

Description: "How your site is doing: conversation volume, average time to first reply, and
conversations that never got one, overall and by channel."

Loads the server's own default window on first render, so it is useful with no interaction. Fields:
**From (optional)**, **To (optional)**, **Apply**. **No date presets.**

Four tables, each with the identical five columns — Conversations, Avg. first response, Avg.
duration, Missed, plus a first column that changes:
1. **by channel** — first row "All channels", then Widget / SMS / MAX / Telegram / WhatsApp.
2. **By operator** — first column is the operator's **first 8 hex characters**, mono.
3. **By referrer** — host, or "Direct".
4. **By campaign** — the raw `utm_campaign` string.

A meta line before the referrer table: "What the visitor's browser reported - not a fact AGO Chat has
independently verified."

**States.** Checking permissions · denied · loading (`Skeleton lines={4}`) · overall count zero
(`.ago-empty`, "No conversations in this range.") · per-table empties, each with its own sentence ·
error, with a distinct message for an inverted range.

### 5.2 `/analytics/conversion` — "Conversion"

Description: "How much benefit this business is getting from its conversations, as operators have
recorded it." Opens with a permanent `Alert tone="info"` stating the rate is built from operator
records, not verified sales.

**Has three preset buttons** — This month / Last month / Last 30 days — above the form. Fields are
labelled **From** and **To** (not "(optional)").

Two tables sharing six columns: Converted, Not converted, Follow-up needed, Not recorded, Conversion
rate (one decimal place, or "—"). The first table has one row, "Whole site", under a **blank column
header**. The second is by operator, again 8 hex characters.

**States.** As above; the empty test is all four counts being zero.

### 5.3 `/analytics/tags` — "Tag report"

Description: "What these conversations are actually about, by tag." Three presets, From/To, Apply.

An `Alert tone="info"` giving coverage as `Tagged 41 / 120 (34.2%)`, or a sentence when there is
nothing to compute from. Then a meta note explaining that a conversation with several tags counts
once per tag so the column will not sum to the total. Then one table: Tag, Conversations, Converted,
Not converted, Conversion rate.

**States.** Two nested empties — "No conversations in this range." (nothing at all) and "No
conversation in this range carries a tag." (conversations exist, none tagged).

### 5.4 `/analytics/booking-flow` — "Booking flow"

Description: "How many conversations started your booking flow, and how many of those flows closed."
**No presets.** From (optional) / To (optional) / Apply.

The result is not a table: a two-item `<dl>` (`.ago-booking-flow-stats`) — "Booking flows started"
and "Flows closed" as 20px numbers — followed by an `Alert tone="info"` carrying a three-sentence
caveat that a closed flow is not a confirmed booking.

**States.** Loading (`Skeleton lines={3}`) · zero flows (`.ago-empty`) · the stats · error.

---

## 6. Site settings

Eight routes. Seven are gated on `site:configure`; `/settings/delete-account` is gated on
`site:erase`. All follow the same skeleton: `PageHead` with a descriptive sentence, an optional
top-level load error, a `Skeleton` inside a `Panel` while loading, then `Panel`s containing forms.
The save control is always a single primary **Save** / "Saving…" button at the bottom, and success is
always a green `Alert` reading "Saved." **No screen warns about unsaved changes on navigation, and
none has a Cancel or Reset.**

### 6.1 `/settings/install` — "Install widget"

Description: "This is what your website needs so visitors can chat with you - your site's own key,
and the web address it's set up to work on."

Three `Panel`s:
1. **Your site key** — the public key as a sunken mono chip + a **Copy key** button. The description
   explains the key is not secret. On copy, a green alert appears and never goes away.
2. **Your website address** — description "The widget only works when your site is opened at exactly
   this address." Body: an unordered list of the allowed origins as mono chips. **When the list is
   empty the panel body renders nothing** — a titled panel with a description and no content and no
   empty state.
3. **Add the chat to your site** — a `<pre>` with the real, working one-line snippet
   (`<script src="…/widget/widget.js" data-site="…" async></script>`, wrapped rather than scrolled)
   and a **Copy the code** button.

**States.** Checking permissions · denied · loading · error · loaded. There is no per-panel error.

### 6.2 `/settings/widget` — "Widget appearance"

Description explains changes take effect on the visitor's next page load.

Two `Panel`s, five controls:
- **Launcher**: *Primary color (hex, optional)* — a text input with a live round colour swatch as its
  `adornment`, defaulting to `#2f6fed` when the input is not a valid hex; *Launcher position* —
  `Select` of Bottom right / Bottom left; *Widget language* — `Select` of English / Русский.
- **Processing notice**: *Notice text (optional)* — a 3-row `Textarea` whose description makes clear
  AGO does not write this sentence for the tenant; *Notice link (optional)* — a URL input that must
  be absolute `https://`.

**States.** Checking permissions · denied · loading (skeleton in a bare panel) · load error ·
per-field validation errors (colour, notice URL) · submit error · saved.
**There is no preview of the widget itself.** The only visual feedback is the colour swatch.

### 6.3 `/settings/faq` — "AI FAQ assistant"

Two independent forms with two independent save buttons on one screen.
1. **Module registration** — *Module key* (placeholder `faq`), *Trigger words* (comma-separated
   free text, e.g. `/faq, /помощь`), *Entry point URL* (absolute https). Three validation messages.
2. **Knowledge base** — a 10-row `Textarea` plus a line reading `Last saved <absolute time>` or
   "Not saved yet."

**A distinct "not configured" state**: when `VITE_FAQ_API_BASE_URL` is unset, the knowledge-base
panel is replaced by an `Alert tone="info"` saying the AI FAQ backend is not configured for this
deployment. The module-registration panel still renders and still saves.

### 6.4 `/settings/auto-reply` — "Offline auto-reply"

One `Panel` containing: a bare checkbox row "Reply automatically when nobody is online"; a
*Default reply* `Textarea`; then a `<fieldset>` "Keyword rules" with an intro explaining first-match
wins, and a repeating row of *Keyword N* + *Reply N* inputs and a **Remove** button. **A blank row is
appended automatically as soon as the last row gains any text** — there is no "Add rule" button. Nine
distinct validation messages, shown one at a time in a danger alert above the save button.

### 6.5 `/settings/canned-responses` — "Canned responses"

Structurally identical to 6.4: one `Panel`, one `<fieldset>` "Responses", repeating *Title N* +
*Text N* (a 2-row `Textarea`) + **Remove**, the same auto-appending blank row, six validation
messages, one Save.

### 6.6 `/settings/tags` — "Tags"

Description: "Labels you can attach to conversations, and use later to filter or count them."

A different editing model from 6.4/6.5 despite being the same shape of problem. One `Panel`
containing a `<ul>` of tag rows. Each row is either **read mode** (the name as text, a **Rename**
button and a danger **Delete** button) or **edit mode** (a labelled *Name* input, **Save**,
**Cancel**). Below the list, a separate small form: *New tag* input + **Create tag** / "Creating…".

Each mutation fires immediately against the server and reloads the list; there is no page-level Save.
**Delete has no confirmation of any kind** — one click removes the tag.

**States.** Checking permissions · denied · loading · load error · `.ago-empty` "No tags yet." · a
row-level error alert inside the panel · a create-level error alert below the create form.

### 6.7 `/settings/billing` — "Billing"

Description: "Your site's current tier, seat usage, and subscription."

**Panel "Subscription"** — three bolded label/value lines: Tier, Seats used, Seat limit. Tier is
rendered as the **raw server value** (`free`, `starter`, …), untranslated. Then, conditionally, up to
five status alerts:
- *Confirming payment* (info, with an inline spinner) while a checkout is pending
- *Payment declined* (danger)
- *Payment retry in progress* (danger)
- *Subscription ending* (info, with the period-end date)
- *Seat change scheduled* (info, with the pending seat count and tier)

**Panel "Subscribe" / "Change seat count"** — hidden entirely while pending or past-due. One numeric
*Seat count* field (2–100, description "The exact price band is confirmed by the server") and a
primary button whose label and action depend on whether a subscription already exists. Success of a
seat change shows `Charged ₽<amount> · <tier>, <seats>.`

**Panel (quiet)** — a danger **Cancel subscription** button, shown only for an active or past-due
subscription that has not already been cancelled. It opens a confirm `Dialog` explaining the paid
tier runs to period end with no refund.

**There is no price, no plan comparison, no invoice history, and no payment-method display** — the
screen shows a tier name, three numbers, and a seat count field. Checkout is a full-page redirect to
the payment provider's hosted page.

### 6.8 `/settings/delete-account` — "Delete account"

**Who.** `site:erase` — a deliberately different gate from every screen above.
One `Panel` "Delete this account" with a paragraph enumerating what is deleted (every conversation,
message and attachment, the site's configuration, its operators, and their sign-in accounts) and one
danger button. The button opens a confirm `Dialog` whose body repeats the warning. There is **no
typed confirmation** ("type the site name to continue") — one click, one dialog, one click.

**A terminal state**: after submission the whole panel is replaced by a danger `Alert` titled
"Deletion in progress" with an inline spinner, telling the reader not to close the page and that they
will be signed out automatically. The nav stays visible and clickable during this.

---

## 7. AGO Calendar screens

Seven routes under `/calendar`, all gated on `calendar:configure`, all sharing a *second* refusal
state the chat screens do not have: when `VITE_CALENDAR_API_BASE_URL` is unset, the page renders a
`PageHead` and an `Alert tone="info"` ("The calendar backend is not configured for this deployment
yet, so this screen cannot be used here.") — the nav entry is still shown, deliberately.

These screens were moved wholesale from a separate `ago-calendar-console` repository (`adr/0093`),
and they still read as a different product. Four differences hold across all seven:

- They have a manual **Refresh** button (in `PageHead`'s `aside`); no calendar screen polls.
- Their empty state is `<Panel><p className="ago-meta">…</p></Panel>`, not `.ago-empty`.
- Their loading state is a `Skeleton` inside a bare `Panel`.
- Several use bare `<ul>`/`<li>` and bare `<pre>` where the chat screens would use `Table`/`Panel`.

### 7.1 `/calendar` — "Queue" (Pending bookings)

Description: "Everything here confirms itself at its deadline unless you reject it first. Ordered by
deadline, soonest first."

One `Table`:

| Column | Content |
|---|---|
| When | `10:30 – 11:15` clock times in the calendar's zone; absolute time in the `title` |
| Calendar | mono, **first 8 hex** of the calendar id — not its name |
| Phone | the phone number, or the meta word "hidden" with a tooltip explaining the missing contact-visibility permission |
| Deadline | clock time, plus a bold " · overdue - the sweep is not running" when overdue |
| Actions | three small buttons: **Reject**, **Cancel**, **No-show** |

All three actions fire immediately with **no confirmation**. All three are the same size, weight and
variant; nothing distinguishes the destructive one.

**States.** Denied · not configured · loading · empty ("Nothing is waiting.") · error alert · rows.

### 7.2 `/calendar/setup` — "Setup"

`PageHead` description is the tenant name. Four `Panel`s:

1. **"Approved page origins"**, whose *description* is actually the embed description ("Paste this on
   your own site. One tag: the chat widget and the booking flow arrive together."). Body: a bare
   `<pre>` embed snippet, then the origins description, then a `Textarea` "One origin per line" and a
   **Save origins** button. The snippet is a placeholder, not a working embed — see section 14.
2. **"Calendars"** — a nested bare `<ul>`: each calendar as `**name** · IANA zone · published/not
   published`, with its working-hours rules as a sub-list (`Monday 09:00–18:00 · <worker name>`).
   Below, a create form: *Calendar name*, *IANA time zone* (a **free-text input** defaulting to
   `Europe/Moscow`, not a picker), a "Published" checkbox, **Add calendar**.
   **There is no edit or delete for a calendar, and no empty state — an empty `<ul>` renders nothing.**
3. **"Services"** — a bare `<ul>` of `name · 45 min`, then a create form (*Service name*,
   *Duration (minutes)*, **Add service**). Again create-only, no empty state.
4. **"Working hours"** — a form: *Worker* `Select`, *Day* `Select` (Sunday…Saturday), *Opens* and
   *Closes* native time inputs, **Add working hours**. Two substitute states: "Add a worker first -
   working hours belong to a worker on a calendar." when there are no workers, and "That worker is
   not on a calendar yet, so there are no hours to give them." beneath a disabled button.
   **Existing rules can be added but not edited or removed from this screen.**

### 7.3 `/calendar/workers` — "Workers"

`PageHead` with a **title only** — no description sentence, unlike every chat screen.

One `Panel` "Workers" containing a `Table`: Name (plus a danger "(needs correction)" badge when the
record was backfilled), Active (success/neutral badge), Created, Updated, Actions.

**The Actions column holds five same-size buttons**: Edit, Schedule, Delete (danger), Slots, Re-cut.
**Edit and Schedule are wired to the identical handler** (`setEditing(worker)`); a code comment says
this is deliberate, "a named shortcut into the same place Edit opens".

Below the table, a primary **Add worker** button, disabled when the tenant has no calendar, with a
meta note "Add a calendar first, on the Setup screen - a worker belongs to exactly one."

Selecting Edit/Schedule/Add replaces the button with a second `Panel` ("New worker" / "Edit worker")
containing `WorkerCard` — Last name, First name, Patronymic, Display name (with a note saying whether
it is derived or hand-set), Calendar `Select`, and a "Services performed" checkbox set — and, when
editing, `WorkerScheduleSection` (template Weekly vs Cycle, anchor date, working/rest days, slot
length, buffer, horizon, "Don't generate before" date, plus a worked arithmetic example sentence) and
a "View slots" link.

**Delete confirmation is not a `Dialog`** — it is a third `Panel` appended below the others,
containing the sentence "Delete <name>? This only works for a worker who has never been booked…" and
**Delete** / **Cancel** buttons. This is the only destructive confirmation in the product that is not
a modal.

**States.** Denied · not configured · loading · error · `<p className="ago-meta">No workers yet.</p>`
returned by `WorkersTable` in place of the table.

### 7.4 `/calendar/workers/:workerId/slots` — "<Name>'s slots"

Reached only from a Workers row action or the edit card's link; **no nav entry**.

`PageHead` (title falls back to "Slots" while the worker is unknown) with a description naming the
calendar's zone, then a `← Workers` link, then a `Panel` with a *From* / *To* date form and a
**Refresh** button.

One `Table`, seven columns: Date (raw ISO `2026-09-04`), Weekday, Time, Status, Service, Customer,
Phone. **Three of the six status labels are raw enum identifiers** —
`PendingConfirmation`, `NoShow`, and `Blocked` sits beside the translated `Available` / `Booked` /
`Cancelled`.

**States.** Denied · not configured · loading · empty ("No slots in this range.") · error · rows.
Nothing on this screen is actionable; it is read-only.

### 7.5 `/calendar/workers/:workerId/recut` — "Re-cut schedule"

Reached only from a Workers row action; **no nav entry**. The only screen in the console that fetches
nothing on mount — it opens as a bare form.

Three sequential stages on one page:
1. A `Panel` with one *Re-cut from* date field and a **Preview** button.
2. The preview: one `Panel` per affected day, titled with the ISO date, containing a count of free
   slots that would be deleted and one row per booking (time range, service, customer, phone, status,
   and a **Cancel / Keep** radio pair — or "Already happened as a no-show - cannot be cancelled, its
   day is kept."). A **Review & confirm** button, disabled until every booking has a decision, with
   the note "Choose cancel or keep for every booking above before continuing."
3. The confirmation `Panel` — a sentence with four bolded counts, a danger `Alert` "This cannot be
   undone from this screen.", and **Confirm re-cut** / **Back**.

Afterwards a "Done" `Panel` summarising days re-cut, days left untouched, slots deleted, slots
inserted and bookings cancelled, plus a list of the dates left in the old grid.

**States.** Denied · not configured · the bare form (initial) · error alert · "Nothing in this range
has been generated yet" info alert · preview · confirm · done. No loading skeleton — the busy state is
only a disabled button.

### 7.6 `/calendar/availability` — "Availability"

`PageHead` with a **title only**, no description.

Two near-identical `Panel`s, each a form:
1. **"Close a day"** — *Worker* `Select` (options read `<worker> · <calendar>`), *Day* date input,
   **Close the day**. Description explains it removes every free slot and leaves a blocking row.
2. **"Change a day's hours"** — the same two fields plus *Opens* and *Closes* time inputs
   (defaulting to `11:00`/`16:00`), **Apply the new hours**.

Success is an `Alert tone="success"` at the top of the page ("The day is closed." / "The day's hours
were changed."). **There is no calendar view, no month grid, no list of days already closed** — the
screen is two write-only forms with no way to see or undo what they did.

**States.** Denied · not configured · loading · load error · a substitute info alert when no worker is
on a calendar ("No worker is on a calendar yet, so there are no days to edit.") · the forms.

### 7.7 `/calendar/contacts` — "Contacts"

Description: "Every customer who has ever booked with this tenant." A `Refresh` button.

One `Table`: Phone, Name (or the meta "not recorded"), Notes (or "—"), No-shows (right-aligned),
First seen, Last seen.

Read-only. **There is no drill-down to a customer's bookings, no search, no filter, and no
pagination control** — the whole list renders at once.

---

## 8. Platform owner

### 8.1 `/owner` — "Platform sites"

**Who.** The platform owner. The route itself is guarded only by `RequireAuth`; the *server* decides,
per request, and the page renders whatever the server answers. It sits outside the operator layout
because a platform owner may have no `operators` row at all — so it renders `AppShell` itself, with no
realtime connection.

**Nav.** If this identity *also* holds an operator seat, the full tenant nav is rendered plus a
"Platform sites" entry; otherwise the nav is just "Platform sites".

**On it.** `PageHead` "Platform sites" and a description that names the reporting window, then one
`Table` with eight columns:

| Column | Content |
|---|---|
| Site | the site name in bold (or the meta "Unnamed") plus a mono badge with the first 8 hex of the site id |
| Tier | neutral badge, raw server value |
| Seats | count, right-aligned |
| Conversations | count, right-aligned (all time) |
| Messages (last N days) | count, right-aligned — the header text carries the window |
| Attachments | a human byte size, exact bytes in the `title` |
| Created | date, or "Not recorded" with a tooltip explaining the platform did not record creation dates then |
| Last activity | date, or a "no recent activity" phrase with a tooltip explaining the window |

Below: a "Showing N sites" / "so far." line and a **Load more** button.

**States.** *Unknown* (a `Spinner` "Opening the platform operations view…") · *refused* (a
`PageHead "Platform operations"` + a danger alert "Not authorized … The server refused the request,
so no site data was loaded.") · *granted, loading* (`Skeleton lines={4}`) · *granted, empty*
(`.ago-empty` "No sites yet.") · *error* (a danger alert; a `PageHead` is only added if access is
still unknown).

**Dead end.** There is no per-site drill-down — no row link, no detail route. The description says so
in words: "Read-only - this screen shows numbers, it changes nothing." There is no action to grant a
product to a tenant, despite the API for it having shipped (see section 14).

**Language.** Deliberately hardcoded English — `OwnerSitesPage` passes the built-in `en` table rather
than calling `useStrings()`, on the reasoning that `/owner` is not scoped to one tenant so it cannot
follow one tenant's language. The i18n assertion in `ux-gate/gate.spec.ts` is skipped for this screen
by name.

---

## 9. The widget

`ago-widget`. One TypeScript bundle a shop drops on its page with a `<script>` tag. Everything renders
inside a Shadow DOM root (`src/ui/shadow-root.ts`, `attachShadow({ mode: "open" })`) whose `:host` is
`all: initial`, so the host page's CSS cannot reach in and the widget's cannot reach out. All styles
are one template string, `src/ui/styles.ts`. All DOM is built imperatively; `textContent`, never
`innerHTML`.

**Configuration comes from the script tag** (`src/config.ts`): `data-site` (required),
`data-api` (else inferred from the script's own origin, else a build-time default),
`data-booking="true"`, and `data-demo-notice="public"|"private"` (or the older
`data-public-demo="true"`). Appearance — colour, launcher side, language, processing-notice text and
link — comes from the server at bootstrap, driven by `/settings/widget` in the console.

**Language.** English and Russian (`src/i18n/`), chosen by the site's configured widget locale.

### 9.1 Closed — the launcher

A 3.5rem circular button, background `--ago-accent` (the tenant's colour, default `#2f6fed`), white
`💬` emoji glyph, drop shadow, `position: fixed` 1.25rem from the bottom and from the right — or from
the left when the site chose Bottom left. `z-index: 2147483647`. `aria-haspopup="dialog"`,
`aria-expanded`, `aria-label` "Open chat".

There is no unread badge, no preview bubble, no attention-grabbing animation, and no greeting prompt.

### 9.2 Open — the panel

A `role="dialog"`, `aria-modal="false"` card anchored to the launcher's own corner:
`width: min(22rem, calc(100vw - 2.5rem))`, `max-height: min(32rem, calc(100vh - 8rem))`,
`bottom: 4.25rem`, 0.75rem radius, its own shadow, `overflow: hidden`. Escape closes it. Focus is
trapped while it is open (`src/ui/focus-trap.ts`).

Top to bottom:
1. **Header** — accent-coloured bar: an `<h1>` "Chat with us", an optional booking chip, and a `✕`
   close button. The header is the only branded element; there is no logo, avatar, or operator name.
2. **Demo notice** (optional) — `.ago-notice`, an amber strip, fixed palette regardless of the
   tenant's colour, not dismissible. Two texts: the public-demo one ("Anyone who opens the demo
   operator console can read what you type here. Do not type anything real.") and the private-tenant
   one.
3. **Processing notice** (optional) — `.ago-processing-notice`, a neutral grey strip carrying the
   tenant's own sentence and, if set, a "Read more" link tinted with the tenant's accent. Hidden when
   the tenant configured no text.
4. **Messages** — `role="log"`, `aria-live="polite"`, `min-height: 12rem`, scrolling.
5. **Status line** — one line of grey text under the messages.
6. **Composer** — a `📎` attach button, a hidden native file input
   (`image/png,image/jpeg,image/gif,image/webp,application/pdf`), a one-row auto-growing textarea
   (`max-height: 6rem`), and a **Send** button. Enter sends; Shift+Enter is a newline.

### 9.3 Message kinds

Five bubble variants, all `max-width: 85%`:

| Variant | Look |
|---|---|
| visitor | right-aligned, accent background, white text, squared bottom-right corner |
| operator | left-aligned, `#f0f1f4`, dark text, squared bottom-left corner |
| auto | as operator, plus a 2px left border and a small uppercase "AUTOMATIC REPLY" label drawn as CSS `content` so it never enters `textContent` |
| system | centred, transparent, grey, smaller |
| pending | any of the above at `opacity: 0.6` until the server echoes it |

A per-bubble `.ago-status` line carries send/upload notes: "Uploading… 43%", "Couldn't send the
attachment.", "Not sure this was sent - the connection dropped mid-request.", "Not sent -
reconnecting. It will not be retried automatically.", "Failed to send." Attachments render as an
inline image (`max-height: 12rem`) or a `📎 Download attachment` link.

**There is no timestamp on any widget bubble, no day separator, no author label, and no read
receipt.** The console thread has all four.

### 9.4 The booking flow, inside the transcript

`src/ui/primitives/render.ts`. Booking is not a separate view — it is ordinary chat messages carrying
structured content. Four `contentKind`s:

- **`choice_list`** — a vertical column of full-width outlined buttons, one per action.
- **`date_time_picker`** — **rendered by exactly the same code path as `choice_list`**: a flat column
  of buttons. There is no calendar, no month grid, no time grid.
- **`confirmation_card`** — an optional bold title and a set of label/value rows
  (`justify-content: space-between`), then the action buttons.
- **`form`** — one label, one text input, one "Continue" submit button. One field per message.

Choosing an option disables every control in that message and sends the chosen label back as a normal
visitor message. Unknown kinds render nothing at all — the bubble shows only its text body.

The booking chip lives in the panel header, is absent unless `data-booking="true"`, and stays hidden
and disabled until its lazily-loaded bundle resolves. Clicking it types the module's trigger phrase.

### 9.5 States

| State | What the visitor sees |
|---|---|
| Bootstrapping | The launcher renders in the widget's built-in default appearance until the session call resolves, then repaints in the tenant's colour and side |
| Connecting | Status "Connecting…", composer disabled, send disabled |
| Connected | Status blank, composer enabled |
| Reconnecting | Status "Reconnecting…", composer disabled |
| Disconnected | Status "Disconnected. Trying to reconnect…", composer disabled |
| Connect failed | Status "Chat is unavailable right now. Please try again later." — terminal for this attempt |
| Session expired | Status "This chat session has expired. Reload the page to start a new one." Everything disabled, the connection stopped, and this state is *sticky*: later connection events cannot overwrite it |
| Previous chat expired | A system bubble: "Your previous chat has expired, so this is a new conversation. Anything you sent before is no longer shown here." |
| File rejected | A note naming the type ("… isn't supported. Try an image or a PDF.") or the size cap |

**There is no empty state.** A brand-new conversation opens to an empty message area with a status
line and a placeholder; nothing greets the visitor, names the shop, or suggests what to ask. There is
also no queue-position or wait-time indicator, and no typing indicator in either direction.

### 9.6 The demo host pages

Four HTML pages ship in the widget repository. They are real surfaces a stranger can open.

- `demo/index.html` — "A very normal shop" / "Hostile host page". A deliberately adversarial host page
  used to prove Shadow DOM isolation. Local-development only (`data-api="http://localhost:5009"`).
- `demo/booking.html` — "Sam & Co, barbers". Shows the chat + booking embed, including a "What the
  shop pastes" section. Local-development only.
- `public-demo/index.html` — the deployed demo shop. **Written in Russian.** Sections: what this page
  is / try it / get your own private tenant / or the shared login — Demo Shop One / is it safe to poke
  around. Carries the tenant-minting panel described below.
- `public-demo-2/index.html` — the second deployed demo shop. **Written in English**, with a
  differently-worded but parallel structure ("Why this page looks different", "Try it", "Get a private
  tenant of your own", "Or, the shared login — Demo Shop Two").

**The minting panel** (`src/demo/panel.ts`) renders one of five outcomes into the page:
- *minted* — "Your own tenant is ready", a lifetime sentence, a loss warning in emphasised text
  ("Copy these now. The password is shown once and is not stored anywhere…"), two read-only
  input+**Copy** field rows (Username, Password), and a two-step ordered list telling the reader to
  open the operator console in a private window and then their own shop page.
- *rateLimited* — "Not so fast", with a retry interval when the server gave one.
- *atCapacity* — "The demo is full".
- *disabled* — "Not available here".
- *failed* — "That did not work" plus the server's detail.

The Copy button changes its own label to "Copied", or to "Press Ctrl+C" after selecting the text when
the clipboard API is unavailable.

---

## 10. Where the layout assumes a desktop

Read from the CSS, not from component names.

**1. The operator workspace is a three-column grid with two fixed tracks.**
`grid-template-columns: 21rem minmax(0, 1fr) 18rem` (`workspace.css`). 39rem — 624px — of the width is
committed before the conversation gets any. Below 74rem the aside is moved above the thread; below
52.5rem the whole thing becomes one column and the rail is hidden whenever a conversation is open.
That last step is the only place in the console where **navigation model** changes rather than column
width: the list and the conversation become alternating full-width views connected by one back link
(`.ago-workspace__back`, `display: none` above 52.5rem).

**2. Below 52.5rem the workspace stops being viewport-height.** `.ago-shell--fixed { height: auto }`
and the thread gets `max-height: 60vh` so the composer stays reachable. The composer is therefore
*not* pinned to the bottom of a phone screen — it sits in document flow after a 60vh-tall thread.

**3. The navigation bar cannot hold its own items.** `.ago-shell__nav` is
`flex-wrap: nowrap; overflow-x: auto` — a horizontally scrolling strip of up to 21 links. Below 40rem
the whole row is `display: none` and replaced by the drawer. `11-14`'s own comment records the
measurement: the bar "does not fit fifteen items at this width". It is now 21.

**4. Every table is `overflow-x: auto` inside a bordered box, with `white-space: nowrap` headers.**
`.ago-table-scroll` / `.ago-table thead th` (`components.css`). There is no card, stacked, or
priority-column mobile treatment anywhere. The widest tables are `/owner` (8 columns),
`/calendar/workers/:id/slots` (7), `/calendar/contacts` (6), `/analytics/conversion` and
`/analytics/tags` (6 each), `/admin` (6 with the erase column). On a 375px viewport these are
side-scrolling regions inside a vertically scrolling page.

**5. The header's identity row packs six controls into one flex row.** Tenancy `Select` + operator
name + site badge + theme `Select` + Sign out. `flex-wrap: wrap` is the only accommodation; the
sub-40rem media query changes only the gap and the operator block's alignment.

**6. `.ago-search-form` is a bottom-aligned wrapping flex row** with `min-width: 16rem` on the phrase
field. On the four report screens and `/search` this puts a date range and a submit button on one line
at desktop width and wraps them into a stack below roughly 500px — a reflow, not a different control.

**7. The composer's action cluster.** Above 40rem, `.ago-composer__row` puts the textarea and a
~235px-wide button group (Attach + Suggest a reply + Send) on one line. The stacking rule at 40rem
exists because that measured 28.5px of textarea at 375px.

**8. Two shell width caps that never apply.** `--ago-content-max` (1088px, the reading measure) is
overridden on every signed-in screen because `OperatorShell` passes `wide` unconditionally. Every
console screen is therefore capped at 1180px and centred.

**9. Hover-only affordances.** The nav's growing underline, `.ago-table tbody tr:hover`, and
`a.ago-list__row:hover` are all hover states. Each has a non-hover counterpart for the *active* case,
so nothing is unreachable, but the "this row is interactive" cue on a table row is hover-only — and
on `/admin` rows are not interactive at all.

**10. Fixed pixel geometry inside components.** `.ago-dialog { width: min(32rem, 100vw - 2rem) }`,
`.ago-shortcuts__row { grid-template-columns: 4.5rem 1fr }`, `.ago-message__thumb { max 7.5rem }`,
`.ago-composer__input { max-height: 12.5rem }`, `.ago-workspace__rail-scroll` and `.ago-aside`
`overflow-y: auto`. These scale with root font size (all `rem`) but not with viewport.

---

## 11. What the widget does on a phone

**It has no viewport media queries at all.** `src/ui/styles.ts` contains exactly one `@media` block,
and it is `prefers-reduced-motion`. Every size is a fixed `rem` or a `min()` clamp. The layout at
375×812 is the desktop layout, shrunk by two clamps.

Concretely, at a 375px-wide viewport:

- The launcher is a 56px circle, 20px from the bottom-right (or bottom-left) corner. That clears the
  24px minimum target size the gate checks, and both viewports are covered by
  `ago-widget/ux-gate/playwright.config.ts` (`mobile-375x812` and `desktop-1280x800`) for overflow,
  target size and contrast.
- The panel is `min(22rem, 100vw - 2.5rem)` = **335px wide** — it does not become a full-screen sheet.
  It floats over the shop's page with ~20px of the page visible on each side and 68px of launcher
  below it.
- The panel is `min(32rem, 100vh - 8rem)` tall. **This uses `vh`, not `dvh`** — unlike the console,
  which uses `100dvh` explicitly and says why. A mobile browser's collapsing address bar and, more
  importantly, the on-screen keyboard do not change `100vh`, so when the keyboard opens the panel
  keeps its full height and the composer is pushed behind the keyboard by the browser's own scroll
  handling rather than by the widget's layout.
- There is no `env(safe-area-inset-*)` anywhere, so on a device with a home indicator the 1.25rem
  bottom offset is measured from the raw viewport edge.
- Message bubbles are `max-width: 85%` — about 285px inside the panel.
- The composer is one row: `📎` + textarea + **Send**. It is not subject to the console's stacking
  rule; it stays a single row at every width.
- The `role="dialog"` is `aria-modal="false"`, so the host page behind the panel remains in the
  accessibility tree and reachable by screen readers while the widget is open. Focus *is* trapped for
  keyboard users (`FocusTrap`), so the two disagree.
- The host page keeps scrolling behind the panel; the widget never locks body scroll.
- `z-index: 2147483647` on `.ago-root` — the maximum 32-bit value — is what keeps it above the shop's
  own fixed elements.

The overflow assertion in `ago-widget/ux-gate/gate.spec.ts` measures the **host page**, not the
widget, deliberately: the claim under test is that dropping the widget on a page does not make that
page scroll sideways.

---

## 12. Inconsistencies I can prove

Each of these is two places in the code doing the same job differently.

**12.1 A supervisor can list every conversation but cannot open one.**
`/admin`'s columns (`AdminConversationsPage.tsx`, `buildColumns`) contain no `Link` — no cell and no
row navigates to `/conversations/:id`. `/search` (`SearchConversationsPage.tsx`, `ResultRow`) *does*
link, but only for `Assigned` conversations, and tells the reader why in words for the other two
states. The same reader, on the same site, with the same permission, gets a drill-down on one screen
and none on the other.

**12.2 Two editing models for "a list of small things the tenant owns".**
`OfflineAutoReplyPage.tsx` and `CannedResponsesPage.tsx` use a batch form: every row is a draft, a
blank row auto-appends when the last gains text, "Leave a row blank to drop it", one Save at the
bottom, validation collected into one alert. `TagsPage.tsx` uses per-row immediate mutation: Rename
toggles a row into edit mode with its own Save/Cancel, Delete fires straight away, Create is a
separate form, and there is no page-level Save at all. `CalendarSetupPage.tsx` uses a third model
again — bare `<ul>` lists that can only be appended to.

**12.3 Destructive actions have three different confirmation strengths.**
`Dialog`-confirmed: close a conversation, erase a conversation, cancel a subscription, delete the
account. `Panel`-confirmed (inline, not modal): delete a calendar worker
(`CalendarWorkersPage.tsx`). Not confirmed at all: delete a tag (`TagsPage.tsx`, `handleDelete`),
and Reject / Cancel / No-show on a pending booking (`CalendarQueuePage.tsx`, the `act` helper).
Rejecting a booking and deleting a tag are one click each.

**12.4 Auto-refresh versus a Refresh button.**
`WorkspaceLayout` polls every 15s; `AdminConversationsPage` polls every 15s and says so in its
description. Every calendar screen has a manual **Refresh** button in `PageHead`'s `aside` and polls
nothing (`CalendarQueuePage.tsx`, `CalendarContactsPage.tsx`, `CalendarWorkerSlotsPage.tsx`). The
booking queue — the one screen with a deadline in every row — is the one that does not refresh itself.

**12.5 Two empty-state idioms.**
Chat and report screens: `<p className="ago-empty">` — a dashed, centred box (`components.css`).
Calendar screens: `<Panel><p className="ago-meta">…</p></Panel>` — grey text in a plain panel
(`CalendarQueuePage.tsx`, `CalendarContactsPage.tsx`, `CalendarWorkerSlotsPage.tsx`,
`WorkersTable.tsx`). Same meaning, two shapes.

**12.6 Date-range presets exist on two of four report screens.**
`ConversionReportPage.tsx` and `TagBreakdownReportPage.tsx` render This month / Last month / Last 30
days. `OperatorAnalyticsPage.tsx` and `BookingFlowConversionPage.tsx` do not. The same two screens
also label their fields **From** / **To** while the other two label them **From (optional)** /
**To (optional)**, and their submit button says **Apply** on all four but the sibling `/search` says
**Search**.

**12.7 Channel names are translated in one place and raw in another.**
`en.ts` has `analyticsChannelSms: "SMS"`, `analyticsChannelMax: "MAX"`, `analyticsChannelTelegram`,
`analyticsChannelWhatsApp` — used in `/analytics`. `ChannelIdentitiesPanel.tsx` renders
`<Badge>{identity.kind}</Badge>` — the raw server enum — and its picker's `<option>`s are the raw
kinds too. `ContactDetailsPanel.tsx` does the same with `detail.kind`.

**12.8 Three slot statuses are raw enum identifiers.**
`en.ts`: `calendarSlotStatusAvailable: "Available"` (translated) sits beside
`calendarSlotStatusPendingConfirmation: "PendingConfirmation"`, `calendarSlotStatusNoShow: "NoShow"`
and `calendarSlotStatusBlocked: "Blocked"`. The Russian table has the same shape. Likewise
`BillingPage.tsx` renders `status.tier` and `sub.pendingTier` raw, and `OwnerSitesPage.tsx` renders
`site.tier` raw.

**12.9 Everybody is eight hexadecimal characters.**
Visitors, operators, sites and calendars are all displayed as `id.slice(0, 8)` in a mono badge —
`ConversationList.tsx`, `AdminConversationsPage.tsx`, `OperatorAnalyticsPage.tsx` and
`ConversionReportPage.tsx` (both define an identical local `operatorLabel`), `CalendarQueuePage.tsx`,
`OwnerSitesPage.tsx`, `AppShell.tsx`'s site badge. Two exceptions: the *tenancy switcher* and
`/owner`'s Site column show a real site name, and `WorkersTable` shows a worker's display name. So
the product does have human names for tenants and staff; it never has one for a visitor or an
operator.

**12.10 Two words for the same navigation target, and one word for two.**
"Conversations" is the nav label for `/`, the rail's own heading, and part of "All conversations" for
`/admin`; `ConversationPage`'s mobile back link says "← Conversations" and points at `/`, while every
permission-refusal page says "Back to queue" and points at the same place. "Queue" in the nav means
the *calendar's* pending bookings.

**12.11 Four screens are English regardless of the tenant's language.**
The console's locale comes from the *site* (`GET /api/v1/operators/me` → `locale`), resolved in
`i18n/resolve.ts`. `/callback`, `/signup`, `/onboarding` and `/owner` never call `useStrings()` —
they hardcode English, including validation messages ("Site display name cannot be empty."). For
`/owner` this is a recorded, deliberate decision; for the other three it is a consequence of their
sitting outside `StringsProvider`, which is mounted inside `OperatorShell`.

**12.12 A `Panel` whose title and description are about different things.**
`CalendarSetupPage.tsx`: `<Panel title={strings.calendarSetupOriginsTitle}
description={strings.calendarSetupEmbedDescription}>` — the title reads "Approved page origins", the
description reads "Paste this on your own site. One tag: the chat widget and the booking flow arrive
together." The embed snippet and the origins editor share one panel.

**12.13 Two identical buttons in the same row.**
`CalendarWorkersPage.tsx`: "Edit" and "Schedule" both call `setEditing(worker)`. A code comment says
this is intentional; the row still offers the operator two differently-labelled buttons that do
exactly the same thing, in a row of five.

**12.14 The widget shows no timestamps; the console shows several.**
Console bubbles carry a `<time>` clock, a day separator, an author label and an absolute timestamp in
the `title`. Widget bubbles carry none of these (`ago-widget/src/ui/widget.ts`,
`appendMessageBubble`). The two ends of the same conversation are timestamped differently.

**12.15 The two public demo shop pages are in different languages.**
`ago-widget/public-demo/index.html` is Russian; `ago-widget/public-demo-2/index.html` is English.
Both are deployed, both describe the same product, and their section headings do not correspond
one-to-one.

---

## 13. What is stubbed, half-built, or dead

**13.1 The calendar's embed snippet is a placeholder, and would not work if pasted.**
**— corrected 2026-09-04; fixed in code, see the corrections section at the end of this document.**
`CalendarSetupPage.tsx`, `embedSnippet()`, rendered literally, at the commit this document was
written against:

```
<script src="https://…/ago-chat.js"
        data-site="YOUR-CHAT-SITE-KEY"
        data-booking="<the tenant's calendar public key>"
        data-booking-api="<the calendar API base URL>"
        async></script>
```

Three things are wrong against `ago-widget/src/config.ts`: the `src` is an ellipsis and a filename
that does not exist (the real bundle is `widget.js`, as `InstallSnippetPage.tsx` emits correctly);
`data-site` is the literal string `YOUR-CHAT-SITE-KEY`; and `readConfig` treats `data-booking` as a
boolean — `bookingModuleEnabled` is `script.dataset["booking"] === "true"`, so a public key there
switches booking **off**. `data-booking-api` is not read by the widget at all (verified by grepping
the whole `ago-widget` source: it appears only in this console file's output, never in the widget).
Meanwhile `ago-widget/demo/booking.html` uses the correct form, `data-booking="true"`.

**13.2 `/signup` is a route with nothing linking to it.** Established in 2.2 above from the code and
its own doc comment.

**13.3 Two calendar routes have no nav entry.** `/calendar/workers/:workerId/slots` and
`/calendar/workers/:workerId/recut` are reachable only from a Workers row action or the worker edit
card. This is stated as deliberate in `App.tsx` and `consoleNav.ts`.

**13.4 A whole product area has an API and no screen: operator management.**
`site:manage-operators` is named in `ago-console/src/api/billingApi.ts` as gating a real server
endpoint (`GetSeatAssignmentSummary`). The console never checks that permission, has no route for it,
and has no UI for inviting, listing, removing or re-roling an operator. `/settings/billing` shows
"Seats used" and "Seat limit" as numbers with no way to see or change who occupies them.
(`docs/backlog/13-01-operator-invitations-and-seat-entitlement.md` is marked **done** — the backend
shipped; the console screen did not.)

**13.5 Conversation transfer has shipped server-side and has no control.**
`docs/backlog/18-02-transfer-a-conversation.md` is marked **done (2026-08-29, `ago-chat#118`)**. A
grep of the whole `ago-console/src` tree for `transfer` returns only an unrelated word in a comment.
There is no transfer button on the conversation header, in the visitor panel, or on `/admin`.

**13.6 Tenant data export has shipped server-side and has no control.**
`docs/backlog/16-03-tenant-data-export.md` is marked **done (2026-08-28, `ago-chat#113`)**. Nothing in
`ago-console/src` mentions an export.

**13.7 The platform owner cannot grant a product to a tenant from the console.**
`docs/backlog/22-17-…md` is marked **done — merged 2026-09-04**, adding the capability to
`/api/v1/owner/`. `ago-console/src/api/ownerApi.ts` contains exactly two functions, both hitting
`GET /api/v1/owner/sites`. `/owner` remains read-only.

**13.8 The Calendar "Access" screen was designed, then deleted, and the gap is recorded.**
`App.tsx` and `consoleNav.ts` both explain that the move from `ago-calendar-console` was to have
brought six screens; `22-05` deleted that product's `operators`/`roles` model along with the endpoints
the sixth screen would have called, so five moved and the sixth was never wired.

**13.9 `/calendar/setup` is excluded from the rendered UX gate.**
`ux-gate/fixtures/screens.ts` covers nine console screens plus the two calendar drill-downs.
`/calendar/setup` is the one deliberate exclusion, because its `<pre>` embed snippet would fail the
gate's "no untranslated interface text" assertion. That same comment states `/settings/install` was
excluded earlier for the identical reason (the file's own five-screens rationale groups it with "the
other four settings screens" without naming the snippet). Either way, the two screens that show an
embed snippet are the two nobody has a screenshot of.

**13.10 The gate's seeded operator holds six permissions, not eleven.**
`ux-gate/fixtures/data.ts`, `seededPermissions()`, grants `conversation:close`, `conversation:erase`,
`attachment:delete`, `site:configure`, `site:erase`, `calendar:configure`. It does **not** grant
`conversation:read`, so in every gate screenshot of `/conversations/:id` the five sub-panels of the
visitor aside (history, tags, notes, outcome, channels, contacts) render as nothing. The screenshots
under `ux-gate/screenshots/` therefore show a shorter aside than a real operator sees.

**13.11 A load failure in `PermissionsProvider` has no user-visible state.**
`src/auth/PermissionsProvider.tsx` catches a failure of `GET /api/v1/operators/me` with
`console.error` and nothing else. `permissions` stays `null`, so every gated page renders its
`<Spinner label="Checking your permissions…">` branch indefinitely, and the nav renders as if the
operator held no permissions at all. There is no timeout, no retry button, and no error message.

**13.12 A copy-confirmation that never clears.**
`InstallSnippetPage.tsx` sets `copied`/`snippetCopied` to `true` and never back; the green "Copied to
clipboard." alerts persist for the life of the mount.

**13.13 `Waiting` conversations are visible in three places and actionable in none.**
The rail's Waiting section is explicitly read-only ("assigned automatically, never claimed here").
`/admin` shows them with no link. `/search` shows them with the note "Unclaimed — assign it from the
queue to open it" — which points at a queue that has no assign action. There is no claim, assign or
take control anywhere in the product.

**13.14 `date_time_picker` is not a date-time picker.**
`ago-widget/src/ui/primitives/render.ts` falls the `date_time_picker` case through to the
`choice_list` case: `case "choice_list": case "date_time_picker": appendActionButtons(...)`. It
renders whatever list of times the server sent as a column of buttons.

**13.15 One environment flag hides a whole screen's main content.**
With `VITE_FAQ_API_BASE_URL` unset, `/settings/faq`'s knowledge-base panel is replaced by an info
alert while the module-registration form still saves. With `VITE_CALENDAR_API_BASE_URL` unset, all
seven calendar screens are info alerts — but their five nav entries still render, deliberately.

---

## 14. What I could not establish

Stated honestly rather than guessed. Each entry names what was looked at.

**14.1 What the screens actually look like.** I read the CSS and the JSX; I did not build, run, or
screenshot either application, and I did not open the deployed environment (the brief forbids it).
Rendered PNGs do exist — `ago-console/ux-gate/screenshots/` and `ago-widget/ux-gate/screenshots/`,
produced at 375×812 and 1280×800 by `npm run ux-gate` in each repository — but both repositories'
`.gitignore` excludes `/ux-gate/screenshots/` and CI publishes them as an upload-artifact instead, so
none is present at the commits I read, and section 13.10 records that the console ones under-represent
the visitor aside. **Anything in this document about spacing, balance, or visual weight is derived
from token values and CSS rules, not from looking.**

**14.2 The Keycloak-hosted screens.** Sign-in, registration, password reset and account management are
Keycloak's pages, not this codebase's. `ago-deploy` carries a login theme
(`k8s/check-theme-tokens.sh` vendors `tokens.css` into it, per a comment in that file) — I did not read
`ago-deploy`, which is outside the two repositories named in the brief. **The first screen a new
tenant ever sees is therefore not inventoried here.**

**14.3 The payment provider's hosted checkout.** `/settings/billing` redirects the whole page to a
`confirmationUrl` returned by the server. What the tenant sees there is the provider's, not ours.

**14.4 The marketing/landing site.** `ago-landing` is a separate repository and was not in scope. It
is referenced by `tokens.css` as the source of the palette and type, and by `shell.css` as the source
of the growing-underline nav idiom, so the console is visually derived from a page this document does
not describe. `docs/design/landing-page-concept.html` exists in this repository and I did not open it.

**14.5 The email surfaces.** `docs/backlog/10-05-transactional-email-delivery.md` exists; I did not
check whether any template ships, and no email template lives in `ago-console` or `ago-widget`.

**14.6 Which of these screens anyone actually uses, and how often.** Nothing in either repository
records usage. Every judgement of importance in this document is structural (what the nav offers,
what a route costs to reach), not empirical.

**14.7 Exact rendered widths at a given viewport.** The CSS gives clamps and breakpoints; the actual
pixel outcome depends on the browser, the root font size and the fonts loading. Two measurements are
quoted here because the code records them as *measured* (the 28.5px composer textarea at 375px in
`workspace.css`, and "does not fit fifteen items" for the nav bar in `shell.css`); I did not
re-measure them and I did not measure anything else.

**14.8 Whether the Russian string table is complete.** `ru.ts` and `en.ts` have 765 and 762
colon-bearing lines respectively — close enough that a shortfall is unlikely, but I compared line
counts, not keys. The type `ConsoleStrings` would make a missing key a compile error, so the risk is
low; I did not verify that by building.

**14.9 The widget's server-driven appearance beyond the four documented knobs.** `appearance.ts`
parses colour, position, notice text and notice URL. Whether the bootstrap response carries anything
else the widget ignores, I did not check against `ago-chat`'s DTO.

**14.10 `WorkerCard` and `WorkerScheduleSection` in full.** I read their string keys (which name every
field and note) and `CalendarWorkersPage`'s use of them, but not their own JSX line by line. The field
list in 7.3 is derived from `en.ts` keys `calendarLastNameFieldLabel` … `calendarSaveScheduleButton`
and is complete as a *field* list; I did not confirm their visual grouping.

---

## Appendix — route index

| Route | Name | Gate | Section |
|---|---|---|---|
| `/callback` | Completing sign-in | none | 2.1 |
| `/signup` | Sign up for AGO Chat | none | 2.2 |
| `/onboarding` | Finish setting up your site | session only | 2.3 |
| `/` | Conversations (queue, nothing open) | session only | 3.1–3.2 |
| `/conversations/:conversationId` | The open conversation | session only | 3.3–3.5 |
| `/admin` | All conversations | `site:configure` | 4.1 |
| `/search` | Search | `site:configure` | 4.2 |
| `/analytics` | Analytics | `site:configure` | 5.1 |
| `/analytics/conversion` | Conversion | `site:configure` | 5.2 |
| `/analytics/tags` | Tag report | `site:configure` | 5.3 |
| `/analytics/booking-flow` | Booking flow | `site:configure` | 5.4 |
| `/settings/install` | Install widget | `site:configure` | 6.1 |
| `/settings/widget` | Widget appearance | `site:configure` | 6.2 |
| `/settings/faq` | AI FAQ assistant | `site:configure` | 6.3 |
| `/settings/auto-reply` | Offline auto-reply | `site:configure` | 6.4 |
| `/settings/canned-responses` | Canned responses | `site:configure` | 6.5 |
| `/settings/tags` | Tags | `site:configure` | 6.6 |
| `/settings/billing` | Billing | `site:configure` | 6.7 |
| `/settings/delete-account` | Delete account | `site:erase` | 6.8 |
| `/calendar` | Queue (pending bookings) | `calendar:configure` | 7.1 |
| `/calendar/setup` | Setup | `calendar:configure` | 7.2 |
| `/calendar/workers` | Workers | `calendar:configure` | 7.3 |
| `/calendar/workers/:workerId/slots` | Worker slots | `calendar:configure` | 7.4 |
| `/calendar/workers/:workerId/recut` | Re-cut schedule | `calendar:configure` | 7.5 |
| `/calendar/availability` | Availability | `calendar:configure` | 7.6 |
| `/calendar/contacts` | Contacts | `calendar:configure` | 7.7 |
| `/owner` | Platform sites | server-side platform owner | 8.1 |
| `*` | — | — | redirects to `/` |

The widget has no routes; its states are listed in 9.5.

---

## Corrections since publication

This document was written against `ago-console` `1eba8d3` and `ago-widget` `5e09304`. Findings it
records are dated; the code moves. Corrections are appended here rather than edited into the body, so
a reader can still see what was true when, and the marker at the affected finding points here.

**2026-09-04 — §13.1, the calendar embed snippet, is fixed.** The finding was filed as `22-22` and
landed in `ago-console` at `a64fcac7f50a3cecec4ea9f217575978bcbaadc8`. `embedSnippet()` now composes
its `src` from `apiBaseUrl` (`…/widget/widget.js`, the same way `InstallSnippetPage` does), emits
`data-booking="true"`, and no longer emits `data-booking-api` — which the widget never read. Three of
the four faults are gone.

The fourth is now deliberate and documented in the code: `data-site` stays the literal placeholder
`YOUR-CHAT-SITE-KEY`, because reading the real chat site key needs `site:configure`
(`GET /api/v1/sites/{siteId}/installation`) and this screen only requires `calendar:configure`.
Fetching it would either fail for a calendar-only operator or widen the screen's own gate. The screen
now carries a hint naming where to get the key, with a link to `/settings/install`.

`22-22` records, and does not answer, the information-architecture question that follows: whether a
tenant should meet two embed snippets at all (§6.1 and §7.2 each show one). The backlog item was
still marked *in review* when this correction was written.
