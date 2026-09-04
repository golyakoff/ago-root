# Brief — platform owner

A join between `flows.md` and `ui-inventory.md`. **Nothing here is new judgement.** Section
references are to `ui-inventory.md`; story numbers are `flows.md`'s.

---

## The role, as `flows.md` states it

**Wants**: to act rarely, safely, and reversibly across tenants.
**The product wants**: that irreversible cross-tenant acts are legible and confirmed, never fast.

*"A handful of people doing things that are irreversible and cross-tenant. Volume is low; the cost of
a mistake is high. Design for confirmation and legibility, never for speed."*

## Every surface this role can reach

**One route.**

| Route | Name | Gate | Inventory |
|---|---|---|---|
| `/owner` | Platform sites | the server's, on every request | §8.1 |

### How the gate actually works, because it is unlike every other screen

§0 and §8.1. The console never reads a platform-owner claim from a token. `RequireAuth` checks only
"is there an OIDC session"; the **server** decides per request, and the page renders whatever it
answers. `useOwnerEligibility` *probes* `GET /api/v1/owner/sites` and treats the server's answer as
the flag — its only job is deciding whether the nav link is drawn.

The route sits **outside** the operator layout, because a platform owner may have no `operators` row
at all: it renders `AppShell` itself, with no realtime connection. If the identity also holds an
operator seat, the full tenant nav is rendered plus a "Platform sites" entry; otherwise the nav is
just that one item.

### What is on it

A `PageHead` and one `Table`, eight columns:

| Column | Content |
|---|---|
| Site | the site name in bold (or the meta "Unnamed") plus a mono badge with the first 8 hex of the site id |
| Tier | neutral badge, **raw server value** |
| Seats | count, right-aligned |
| Conversations | count, right-aligned, all time |
| Messages (last N days) | count; the header text carries the window |
| Attachments | a human byte size, exact bytes in the `title` |
| Created | date, or "Not recorded" with a tooltip explaining the platform did not record creation dates then |
| Last activity | date, or a "no recent activity" phrase with a tooltip explaining the window |

Below: a "Showing N sites" / "so far." line and a **Load more** button (a cursor, never page numbers).

### States it has

*Unknown* (a `Spinner`, "Opening the platform operations view…") · *refused* (a
`PageHead "Platform operations"` and a danger `Alert`: *"Not authorized … The server refused the
request, so no site data was loaded."*) · *granted, loading* (`Skeleton lines={4}`) · *granted,
empty* (`.ago-empty` "No sites yet.") · *error* (a danger alert; a `PageHead` is added only if access
is still unknown).

### Language

Deliberately hardcoded English — `OwnerSitesPage` passes the built-in `en` table rather than calling
`useStrings()`, because `/owner` is not scoped to one tenant so it cannot follow one tenant's
language. The console's i18n assertion in `ux-gate/gate.spec.ts` is skipped for this screen by name
(§8.1, §12.11).

## Mobile constraints that apply

From §10.

- **Eight columns is the widest table in the product** (§10.4). `.ago-table-scroll` is
  `overflow-x: auto` with `white-space: nowrap` headers; there is no card or stacked treatment at any
  width. On a 375px viewport this is a side-scrolling region inside a vertically scrolling page.
- Two of the eight columns carry meaning **only in a native `title` tooltip** — the exact byte count,
  and both "not recorded" explanations. Tooltips do not appear on touch and cannot be styled
  (§12 / the Dialog card: *"every explanatory hover in the console is a native `title` attribute"*).
- The screen is not viewport-height; it scrolls as an ordinary page (§1).
- The header's identity row and the nav behave exactly as elsewhere (§10.5, §1).

---

## 5.1 Seeing every tenant — `built`

### Surfaces

`/owner` (§8.1), as above. This story is a **critique of a built screen**.

### What the story asks for that the screen already does

- *"Must be able to trust that the list is complete."* The screen renders whatever the server's
  cross-tenant read returns, and `flows.md` records that this is asserted in a test
  (`PlatformOwnerAsTenantTests`) rather than assumed. Nothing in the console re-scopes it.
- The description sentence states the reporting window in words and distinguishes the windowed
  columns (message volume, last activity) from the all-time ones (seats, conversations, stored
  bytes).

### States this story requires that do not exist

- **The story**: *"so that I can find the one I am being asked about."* **The inventory** (§8.1):
  there is **no search, no filter and no sort** on this table — `Table` has none (§10.4 / the Table
  card), and paging is a cursor-ordered **Load more**, in the API's own order (site id, descending),
  *"not ranked by size or activity"* as the caption says. Finding a named tenant means loading pages
  until it appears.
- **The inventory** (§8.1): **there is no per-site drill-down** — no row link, no detail route. The
  description says so in words: *"Read-only - this screen shows numbers, it changes nothing."*

### Facts that bear on it

- §12.8 — the Tier column renders the raw server value, as `/settings/billing` does.
- §12.9 — the Site column is one of only three places in the product with a human-readable name (the
  others being the tenancy switcher and calendar workers).

---

## 5.2 Granting a product to a tenant without payment — `built as an API, **no screen at all**`

### Surfaces

**None.** §13.7: `ago-console/src/api/ownerApi.ts` contains exactly two functions, both hitting
`GET /api/v1/owner/sites`. `/owner` is read-only.

The capability landed: `docs/backlog/22-17-*.md` is marked **done — merged 2026-09-04**
(`ago-calendar#38`, `ago-chat#166`), with `adr/0098`. `flows.md` states the same:
*"`22-17`, `adr/0098` — API only."*

### Everything this story needs is absent

- no grant surface, no revoke surface, no list of grants
- no expiry field, and nothing anywhere in the console that displays an `ExpiresAt`
- no audit or "who granted this and when" surface
- no per-site detail screen for any of it to live on (§8.1)

### The states the story specifies, none of which exist

Recorded here because they are unusually specific and a designer will need them:

- **The story**: *"Must be able to state an end date **or explicitly state there is none** — a grant
  with no expiry is a discount nobody remembers giving."* Two distinct states, neither present.
- **The story**: *"Must not be made to believe expiry does more than it does. **`ExpiresAt` binds the
  granting side only**: chat stops offering the module the instant it lapses, and **the module is
  never told**. A screen presenting expiry as a clean end date would be lying to its own author."*
  This is a required *honesty* state with no precedent in the console — the nearest analogues are the
  four standing caveats on the report screens (see the tenant brief, 4.4), all of which are
  `Alert tone="info"` in normal flow.
- **The story**: *"Must never happen: this becoming the ordinary path to having a product."*

### The nearest existing patterns, for vocabulary

| Pattern | Inventory | Where |
|---|---|---|
| a confirmed irreversible act | §3.3, §4.1, §6.7, §6.8 | `Dialog` with a ghost Cancel and a danger confirm whose label names the act ("Close it", "Erase it", "Delete it") |
| a standing honesty caveat | §5.2, §5.3, §5.4 | `Alert tone="info"` in normal flow, never dismissible |
| a "this is not what it looks like" tooltip | §8.1 | native `title` — invisible on touch |
| an add-on that is enabled but not usable | §13.15 | the five calendar nav entries render with the backend unset; the screen behind each is an `Alert tone="info"` |

---

## 5.3 Repairing a tenant — `partial`

### Surfaces

| Route | Inventory | What it can do |
|---|---|---|
| `/owner` | §8.1 | read eight numbers per site. **Nothing else** |
| `/settings/billing` | §6.7 | the *tenant's own* screen, reachable only with `site:configure` **for that site** — the owner has no route to another tenant's settings |

`flows.md`: *"Must not be made to write SQL against a live tenant, which is the remedy today."*

### States this story requires that do not exist

- **The story**: *"Must be able to see the tenant's actual state and act on it."* §8.1: eight
  aggregate numbers, no drill-down, no subscription detail, no provisioning status. The tenant's own
  billing screen (§6.7) shows five conditional status alerts — *Confirming payment*, *Payment
  declined*, *Payment retry in progress*, *Subscription ending*, *Seat change scheduled* — and none of
  those states is visible from `/owner`.
- **The story**: *"Must never happen: undoing something without seeing it was not yours. Revoke works
  on a tenant's **own purchase** as readily as on a grant — an owner can undo something they did not
  do, and **that asymmetry has to be visible at the moment of acting**."* No surface distinguishes a
  granted entitlement from a purchased one, because no surface shows either.
- **The story**: *"How we know it worked. Time from support ticket to the customer having what they
  paid for."* Nothing is instrumented or displayed for this.

### Facts that bear on it

- §8.1 — the *refused* state is worth reading before designing any owner action: it renders a
  `PageHead` and a danger `Alert` and **loads no data at all**, which is the correct shape for a
  cross-tenant refusal and the only one in the product.
- §12.11 — everything here is hardcoded English on purpose, and the console's translation gate skips
  this screen by name. Any new owner surface inherits that decision or breaks it deliberately.
- §13.11 — the console-wide failure mode applies here too: `PermissionsProvider` failing leaves a
  Spinner forever. `/owner` has its own three-state access model (`unknown` / `granted` / `refused`)
  which does **not** share that defect — its `unknown` state has a Spinner, and its error state has a
  message.

---

## Cross-cutting facts from the inventory that touch every platform-owner story

- **§1** — a platform owner who is *also* an operator gets the full tenant nav plus "Platform sites",
  flat, in one horizontally scrolling strip of up to 21 items with no grouping and no break between
  tenant screens and cross-tenant ones. The only thing that marks the difference is the tagline
  changing to "Platform owner console".
- **§1** — the demo notice has a distinct platform-owner text, chosen by `useOwnerEligibility`. It is
  the one place the interface addresses this role in words.
- **§0** — this is the only role in the product not expressed as a permission. The other four are
  combinations of the eleven grants; this one is a Keycloak realm role the console never reads
  directly, and `flows.md` records that **no write in this codebase grants that role** — *"that is
  the answer, not an omission."*
- **§10.4** — every table in the product, including this one, is a horizontal-scroll region with no
  responsive treatment. An owner acting from a phone during a support call meets an eight-column
  table.
