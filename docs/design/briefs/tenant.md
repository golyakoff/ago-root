# Brief — tenant

A join between `flows.md` and `ui-inventory.md`. **Nothing here is new judgement.** Section
references are to `ui-inventory.md`; story numbers are `flows.md`'s.

---

## The role, as `flows.md` states it

**Wants**: to know whether this is making them money, and to spend well.
**The product wants**: to be honestly worth keeping — including saying when it is not yet.

*"Every screen they see is either onboarding or troubleshooting — there is no third mode, and
treating these as ordinary settings pages is the mistake most worth undoing. The interface must read
as **grown-up**."*

## Every surface this role can reach

Thirteen routes behind `site:configure`, one behind `site:erase`, plus the two pre-session routes.
This is where all but one of the console's twenty-one nav items live.

| Route | Name | Gate | Inventory |
|---|---|---|---|
| `/signup` | Sign up for AGO Chat | none | §2.2 |
| `/callback` | Completing sign-in | none | §2.1 |
| `/onboarding` | Finish setting up your site | session only | §2.3 |
| `/admin` | All conversations | `site:configure` | §4.1 |
| `/search` | Search | `site:configure` | §4.2 |
| `/analytics` | Analytics | `site:configure` | §5.1 |
| `/analytics/conversion` | Conversion | `site:configure` | §5.2 |
| `/analytics/tags` | Tag report | `site:configure` | §5.3 |
| `/analytics/booking-flow` | Booking flow | `site:configure` | §5.4 |
| `/settings/install` | Install widget | `site:configure` | §6.1 |
| `/settings/widget` | Widget appearance | `site:configure` | §6.2 |
| `/settings/faq` | AI FAQ assistant | `site:configure` | §6.3 |
| `/settings/auto-reply` | Offline auto-reply | `site:configure` | §6.4 |
| `/settings/canned-responses` | Canned responses | `site:configure` | §6.5 |
| `/settings/tags` | Tags | `site:configure` | §6.6 |
| `/settings/billing` | Billing | `site:configure` | §6.7 |
| `/settings/delete-account` | Delete account | `site:erase` | §6.8 |

## The shape every settings screen shares

§6: `PageHead` with a descriptive sentence, an optional top-level load error, a `Skeleton` inside a
`Panel` while loading, then `Panel`s containing forms. The save control is always a single primary
**Save** / "Saving…" at the bottom, and success is always a green `Alert` reading "Saved."

**No screen warns about unsaved changes on navigation, and none has a Cancel or Reset.**

## Mobile constraints that apply to every story below

From §10.

- Every table is `overflow-x: auto` with `white-space: nowrap` headers, with no card or stacked
  treatment at any width (§10.4). The tenant's widest are `/analytics/conversion` and
  `/analytics/tags` at six columns each, and `/admin` at six with the erase column.
- `.ago-search-form` — the date range on `/search` and all four reports — is a bottom-aligned
  wrapping flex row with `min-width: 16rem` on the phrase field; it wraps into a stack below roughly
  500px (§10.6).
- The header's identity row packs six controls into one wrapping flex row: tenancy `Select`,
  operator name, site badge, theme `Select`, Sign out (§10.5).
- Below 40rem the 21-item nav becomes the hamburger drawer (§1).
- None of these screens is viewport-height; they scroll as ordinary pages (§1).
- `--ago-content-max` (the 1088px reading measure) never applies: `OperatorShell` passes `wide`
  unconditionally, so every one of these screens is capped at 1180px (§10.8).

---

## 4.1 Getting from signed-up to working — `partial`, and `flows.md` calls it **the weakest flow in the product**

### Surfaces, in the order this person meets them

| Route | Inventory | What is on it | Language |
|---|---|---|---|
| `/signup` | §2.2 | a `PageHead` and **one primary button**. No form, no fields. **Nothing in the console links here** — the route exists to be linked from outside | hardcoded English |
| Keycloak's own registration | §14.2 | **not in this bundle or the inventory** — it lives in `ago-deploy` and reads a vendored, light-only copy of the console's tokens | Keycloak's |
| `/callback` | §2.1 | `CenteredShell` + a `Spinner`. Three failure states, two of which are **dead ends whose only instruction is "reload"** | hardcoded English |
| `/onboarding` | §2.3 | a two-field form: *Site display name*, *Embed origin*. Header carries identity and Sign out but **no nav** | hardcoded English, including validation messages |
| `/settings/install` | §6.1 | three `Panel`s: Your site key (+ Copy), Your website address, Add the chat to your site (a working `<pre>` snippet + Copy) | the site's locale |

### States they have

`/onboarding`: idle · submitting · one client validation message at a time · server error · a
platform-owner info alert. A `Site.AlreadyRegistered` answer navigates to `/` silently — the user
sees a flash, not a message.

`/settings/install`: checking permissions · denied · loading · error · loaded.

### States this story requires that do not exist

- **The story**: *"Must be able to find out **that it is working**, from their own site, without
  reading anything technical."* **The inventory**: no verification, test-connection, or
  "we-have-seen-your-site" state exists on `/settings/install` (§6.1) or anywhere else. `10-06`
  exists because *the tenant never learns how to install the widget*.
- **The story**: *"Must not be made to guess whether silence means not installed, installed and
  nobody has written, or broken."* **The inventory** (§13, §3.1): an empty queue renders
  `.ago-empty` "Nothing assigned yet. New conversations arrive here automatically." — the same
  sentence a long-running site sees after a quiet week. §13 records this generally: *there is no
  first-run or zero-data state anywhere; nothing distinguishes "you have not set this up yet" from
  "nothing happened this week".*
- **The story**: *"Must be able to get help installing it when they cannot do it themselves — a real
  and common case."* No contact, help or hand-off surface exists on any console screen.
- **The story**: *"Must want to finish the setup rather than defer it, which means each step visibly
  ends."* No progress, checklist or step indicator exists. `/onboarding` navigates to `/` and the
  operator lands in an empty queue with a 21-item nav.
- **The inventory** (§6.1): the *"Your website address"* panel **renders nothing in its body when the
  origin list is empty** — a titled panel, a description, and no content and no empty state.
- **The inventory** (§12.11): `/signup`, `/callback` and `/onboarding` are hardcoded English
  regardless of the tenant's language, because they sit outside `StringsProvider`. A Russian-speaking
  tenant's first three screens are in English, and the fourth is not.

### The fact that made this story's "must never happen"

**The story**: *"Must never happen: being handed something that cannot work. `22-22` is exactly that
— the calendar embed snippet was broken four ways and one of them failed silently."*

`ui-inventory.md` §13.1 recorded that finding. **It has since been fixed** in `ago-console` at
`a64fcac`: the snippet composes its URL from `apiBaseUrl`, emits `data-booking="true"`, and drops the
`data-booking-api` attribute the widget never read. The chat site key remains a deliberate
placeholder — reading it needs `site:configure` and that screen only requires `calendar:configure` —
and the copy now names where to get it and links to `/settings/install`. The backlog item is still
marked *in review*. **`ui-inventory.md` §13.1 is stale on this point.**

`22-22` also records, and does not answer, an information-architecture question this story touches:
whether a tenant should meet two embed snippets at all (§6.1 and §7.2 both show one).

---

## 4.2 Switching on the calendar — `partial`

### Surfaces

| Route | Inventory | Relevance |
|---|---|---|
| `/settings/faq` | §6.3 | the **only** module-enablement surface that exists, and it is for a different module |
| `/settings/billing` | §6.7 | tier, seats used, seat limit, and a checkout redirect. No module or add-on concept |
| the five `/calendar/*` nav entries | §1, §13.15 | drawn whenever the identity holds `calendar:configure`, **whether or not the backend is configured** |
| any `/calendar/*` route | §7 | with `VITE_CALENDAR_API_BASE_URL` unset: a `PageHead` and an `Alert tone="info"` — "not configured for this deployment yet" |

### The central fact

There is **no screen on which a tenant switches the calendar on**. `flows.md`: *"Module enablement
(`19-03`, `22-11`). The paid version with a quota is `22-07` — planned. An owner can grant it without
payment (`22-17`) — API only."* The inventory agrees: no route in `App.tsx` offers a feature list, an
add-on, or a purchase of anything but seats (§6.7).

### States this story requires that do not exist

- **The story**: *"Must be able to see what is different afterwards, what it costs, and what they
  must do next — because enabling a module is a **before/after**, not a toggle."* No before/after
  surface exists. The closest is §6.3's module-registration form, which asks for a module key,
  trigger words and an entry-point URL — a technical registration, not a purchase.
- **The story**: *"Must not be made to discover the setup work after committing."* §7.2's four panels
  and §7.3's schedule template are the setup work, and nothing names it before a tenant reaches them.
- **The inventory** (§6.7): `/settings/billing` shows **a tier name, three numbers and a seat-count
  field**. There is no price, no plan comparison, no invoice history and no payment-method display.
  The tier renders as the **raw server value** (`free`, `starter`) — §12.8.
- **The inventory** (§13.15): the five calendar nav entries are drawn even when the backend is unset,
  deliberately. `flows.md`'s own trap — *absent and forbidden look identical* — is inverted here:
  present and unusable look like present.

---

## 4.3 Giving a colleague access — `built` per `flows.md`; **no screen exists** per the inventory

### The disagreement, stated plainly

`flows.md` marks this `built`, and the backlog agrees: `13-01` (operator invitations and seat
entitlement) is marked **done — merged `ago-chat#109`/`ago-root#235` (2026-08-28)**.

**The inventory records that the console has no surface for it** (§13.4): there is no route, no nav
entry and no UI for inviting, listing, removing or re-roling an operator. The permission that gates
the server side, `site:manage-operators`, is named in a comment in `ago-console/src/api/billingApi.ts`
and is **never checked by the console** — it is not one of the eleven permissions any screen reads
(§0, the permission vocabulary).

So: the capability is built, and the tenant cannot reach it. A story about a screen that does not
exist is a proposal; this one is filed as a critique. That is worth resolving before design starts.

### The nearest surfaces

| Route | Inventory | What it shows about operators |
|---|---|---|
| `/settings/billing` | §6.7 | **Seats used** and **Seat limit** as two numbers, with no way to see or change who occupies them |
| `/analytics`, `/analytics/conversion` | §5.1, §5.2 | a **By operator** table whose first column is `operatorId.slice(0, 8)` in mono |
| `/admin` | §4.1 | an **Assigned operator** column, same eight hex characters, or the meta word "Unassigned" |

### States this story requires that do not exist

- **The story**: *"Must be able to think in jobs and have the system translate to permissions — the
  recurring failure is that permissions are shown as capabilities and understood as job titles."*
  There is no role, job or grant surface at all. The eleven permissions appear nowhere in the
  interface; they appear only as the invisible gate that draws or does not draw a nav item (§1).
- **The story**: *"Must never happen: a person granted access who sees nothing and cannot tell why.
  This is `22-14`'s lesson generalised: absent and forbidden look identical."* **The inventory**
  (§13, states card): *"A permission-gated nav item is simply not drawn, so a person who lacks a
  grant sees exactly what a person for whom the feature does not exist sees."* The denied pattern —
  `PageHead` with no description, a danger `Alert`, a "Back to queue" link — appears **only** to
  someone who reached the URL directly. There is no state for "this exists and you may not use it".
- **The story**: *"Must not be made to learn an eleven-permission vocabulary to add a receptionist."*
  §12.9 compounds it: an operator has no name anywhere in the interface, so even a list would be
  eight hex characters.

---

## 4.4 Seeing whether this is paying off — `partial`

### Surfaces

| Route | Inventory | Content |
|---|---|---|
| `/analytics` | §5.1 | four tables sharing five columns — Conversations, Avg. first response, Avg. duration, Missed — cut by channel, operator, referrer, campaign |
| `/analytics/conversion` | §5.2 | two tables, six columns: Converted, Not converted, Follow-up needed, Not recorded, Conversion rate |
| `/analytics/tags` | §5.3 | a coverage `Alert` (`Tagged 41 / 120 (34.2%)`) and one table: Tag, Conversations, Converted, Not converted, Conversion rate |
| `/analytics/booking-flow` | §5.4 | a two-item `<dl>` and a three-sentence caveat |
| `/settings/billing` | §6.7 | what they are paying |

### What already serves the story's honesty rule

The inventory records four standing caveats already on these screens, in the product's own words:

- `/analytics/conversion` opens with a permanent `Alert tone="info"`: the rate is built from what
  operators recorded, *"not from a verified sale or order"*.
- `/analytics` carries *"What the visitor's browser reported - not a fact AGO Chat has independently
  verified."* before the referrer table.
- `/analytics/tags` carries a note explaining that a multi-tagged conversation counts once per tag,
  *"so this column will not sum to the total … that is expected, not an error."*
- `/analytics/booking-flow` carries a three-sentence caveat that a closed flow is not a confirmed
  booking.
- The outcome panel carries *"Recorded by the operator - not a sale AGO Chat has independently
  verified."* (§3.4).

### States this story requires that do not exist

- **The story**: *"Must be able to ask **what if**: what happens if we add a chair, extend hours,
  answer faster."* **The inventory**: no forecasting, projection or scenario surface exists on any
  of the four report screens. There is no state to label as a projection because there are no
  projections.
- **The story**: *"Must want to look at it, which means it must be readable in a minute."* **The
  inventory** (§5): *"None of them contains a chart, a sparkline, a trend arrow, or any graphical
  element. Every number is a table cell."* There is also no comparison to a previous period on any of
  the four.
- **The story**: *"Must never happen: inflated, flattered, or selectively-good numbers … the product
  says so when it is not yet paying off, with why."* There is no state that says a number is bad. The
  empty states are neutral — "No conversations in this range." — and the same sentence covers a new
  site and a dead month (§13).
- **The story**: *"see what happened … and **what it is attributable to**."* The by-referrer and
  by-campaign tables exist (§5.1) and carry the browser-reported caveat. Nothing attributes a booking
  or a sale to a conversation beyond §5.4's two counts.
- **The inventory** (§12.9, and `flows.md` repeats it): the By-operator column is eight hex
  characters — *"the reports name operators the reader cannot identify."*

### Facts that bear on it

- §12.6 — two of the four reports have date presets (This month / Last month / Last 30 days) and two
  do not; the same two label their fields **From**/**To** while the others say **From
  (optional)**/**To (optional)**.
- §5.2 — the conversion report's overall table has **one row under a blank column header**.
- §5.1 — `/analytics` loads the server's default window on first render, so it is useful with no
  interaction. The other three require a submit (or a preset click) before they show anything.

---

## 4.5 Finding out what happened to a message — `partial`

### Surfaces

| Route | Inventory | What it can answer |
|---|---|---|
| `/search` | §4.2 | full-text across the site, newest first, with a date range. A result links to the conversation **only when its state is `Assigned`** |
| `/admin` | §4.1 | every conversation with state, operator, start, unread — **and no link to any of them** |
| the conversation thread | §3.3 | timestamps per message; **no per-message delivery state** |

### States this story requires that do not exist

- **The story**: *"Must be able to answer **did it send** without reading a log or asking support."*
  **The inventory** (§3.3): *"No per-message delivery state. Operator bubbles show a timestamp; there
  is no sent / delivered / read indicator anywhere."* `flows.md` agrees from the other side:
  *"Delivery outcomes are recorded. The surface for a non-technical person is largely absent."*
- **The story**: *"Must not be made to interpret a delivery status that means something only to an
  engineer."* The one delivery-adjacent state a tenant can meet is the composer's *"Send failed or is
  unconfirmed"* danger `Alert` quoting the failed body (§3.3) — and that is the operator's screen at
  the moment of failure, not a later lookup.
- **The story's moment** is *"a tenant whose customer says they got nothing"* — that is a lookup by
  person. §4.2's search is by phrase; §4.1 has no filter but a tag `Select`; and §12.9 means there is
  no name to look up by.
- **The inventory** (§4.2): `/search`'s initial state is *"the form and nothing else — no prompt, no
  recent searches, no empty illustration"*, and a standing note warns that only the shown date range
  is searched and older conversations *"may still exist but [are] not reachable from here."*

---

## Cross-cutting facts from the inventory that touch every tenant story

- **§12.2** — three different editing models for "a list of small things the tenant owns", across
  three sibling settings screens: batch draft with auto-appending blank rows and one Save
  (`/settings/auto-reply`, `/settings/canned-responses`), per-row immediate mutation with no
  page-level Save (`/settings/tags`), and append-only bare `<ul>`s (`/calendar/setup`).
- **§12.3** — three confirmation strengths for destructive acts. `Dialog`: close a conversation,
  erase a conversation, cancel a subscription, delete the account. Inline `Panel`: delete a calendar
  worker. **None at all**: delete a tag, and Reject / Cancel / No-show on a booking.
- **§6.8** — deleting the account is one click, one dialog, one click. There is **no typed
  confirmation**.
- **§12.1** — a supervisor can list every conversation and open none of them.
- **§13.6** — tenant data export shipped server-side (`16-03`, marked done 2026-08-28) and nothing in
  `ago-console/src` mentions an export.
- **§13.11** — when `PermissionsProvider`'s fetch fails it logs to the console and nothing else:
  every gated screen renders "Checking your permissions…" **indefinitely**, with no timeout, no retry
  and no message, and the nav renders as if the tenant held no permissions at all.
- **§13.12** — the "Copied to clipboard." confirmations on `/settings/install` never clear.
- **§1** — the tagline that names the product changes to "Client console" on exactly five routes, by
  a hand-maintained `useMatch` list. Eight of the thirteen `site:configure` screens are not in it.
