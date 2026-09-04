# Brief — calendar operator

A join between `flows.md` and `ui-inventory.md`. **Nothing here is new judgement.** Section
references are to `ui-inventory.md`; story numbers are `flows.md`'s.

---

## The role, as `flows.md` states it

**Wants**: the schedule to reflect reality with the least disruption to people already booked.
**The product wants**: capacity that is accurate, and changes that do not cost customers.

*"A different job from chat, wearing the same login since `22-05`. The unit of work is a week, not a
message, and the expensive moments are the ones that touch a customer who already booked."*

## Every surface this role can reach

All seven are gated on `calendar:configure`, a grant independent of `site:configure` (§1).

| Route | Name | Nav entry | Inventory |
|---|---|---|---|
| `/calendar` | Queue — pending bookings | yes | §7.1 |
| `/calendar/setup` | Setup | yes | §7.2 |
| `/calendar/workers` | Workers | yes | §7.3 |
| `/calendar/workers/:workerId/slots` | Worker slots | **no** — row action only | §7.4 |
| `/calendar/workers/:workerId/recut` | Re-cut schedule | **no** — row action only | §7.5 |
| `/calendar/availability` | Availability | yes | §7.6 |
| `/calendar/contacts` | Contacts | yes | §7.7 |

An eighth screen — Access — was designed and never wired: `22-05` deleted that product's
`operators`/`roles` model and the endpoints it would have called (§13.8).

## What these seven share, and what makes them visibly a different product

§7 records four differences that hold across all of them. They moved wholesale from a separate
repository under `adr/0093` and kept their own idioms:

- **A manual `Refresh` button** in `PageHead`'s `aside`; **no calendar screen polls.** The chat
  workspace polls every 15s and `/admin` says so in its description (§12.4). *The booking queue — the
  one screen with a deadline in every row — is the one that does not refresh itself.*
- **A second empty-state idiom**: `<Panel><p className="ago-meta">…</p></Panel>` rather than
  `.ago-empty`'s dashed centred box (§12.5).
- Loading is a `Skeleton` inside a bare `Panel`.
- Several use bare `<ul>`/`<li>` and bare `<pre>` where the chat screens use `Table`/`Panel`.

Every one of the seven also has a **second refusal state** the chat screens do not have: when
`VITE_CALENDAR_API_BASE_URL` is unset they render a `PageHead` and an `Alert tone="info"` — *"The
calendar backend is not configured for this deployment yet"* — while their five nav entries stay
visible, deliberately (§13.15).

## Mobile constraints that apply to every story below

From §10. `flows.md`'s standing note applies hardest here: *"Three of the five roles are often the
same human. A one-chair salon owner is tenant, chat operator and calendar operator, on a phone,
between customers."*

- **Every table is `overflow-x: auto` inside a bordered box, with `white-space: nowrap` headers**
  (§10.4). There is no card, stacked or priority-column treatment at any width. The calendar's own
  widest tables are worker-slots (7 columns) and contacts (6).
- On a 375px viewport these are side-scrolling regions inside a vertically scrolling page.
- The calendar screens are **not** viewport-height: only `/` and `/conversations/:id` pass `fixed`
  (§1). They scroll as ordinary pages.
- `.ago-search-form` — the bottom-aligned wrapping flex row used by the slots date range — wraps into
  a stack somewhere below roughly 500px. That is a reflow, not a different control (§10.6).
- Below 40rem the whole nav bar is replaced by the hamburger drawer, which lists all five calendar
  entries among the other sixteen, flat (§1).
- Hover-only row tinting applies to these tables as it does to every other (§10.9).

---

## 3.1 Setting up a master — `built`

### Surfaces

| Route | Inventory | What is on it |
|---|---|---|
| `/calendar/setup` | §7.2 | four `Panel`s: **Approved page origins** (embed snippet + a one-origin-per-line `Textarea` + Save origins), **Calendars**, **Services**, **Working hours** |
| `/calendar/workers` | §7.3 | a `Table` (Name, Active, Created, Updated, Actions) plus an inline `WorkerCard` edit panel and `WorkerScheduleSection` |

### What "Calendars" and "Services" actually are

§7.2: **nested bare `<ul>` lists**. A calendar renders as `**name** · IANA zone ·
published/not published`, with its working-hours rules as a sub-list. A service renders as
`name · 45 min`. Below each list is a create form. **There is no edit and no delete for a calendar or
a service, and no empty state — an empty `<ul>` renders nothing.**

The time zone is a **free-text `Input`** defaulting to `Europe/Moscow`, not a picker.

Working hours can be added but not edited or removed from this screen.

### States it has

Denied · not configured · loading · load error · the four panels. Two substitute states inside the
working-hours panel: *"Add a worker first - working hours belong to a worker on a calendar."* and
*"That worker is not on a calendar yet, so there are no hours to give them."* On `/calendar/workers`:
**Add worker** is disabled with no calendar, beneath the note *"Add a calendar first, on the Setup
screen - a worker belongs to exactly one."*

### States this story requires that do not exist

- **The story**: *"Must be able to reach a bookable state without understanding the model first, and
  **find out what is still missing**."* **The inventory**: there is no progress, checklist or
  readiness state anywhere in §7.2 or §7.3. The two substitute notes above are the only "what is
  missing" signals, and each appears only inside the panel that is already blocked.
- **The story**: *"Must never happen: a setup that looks finished and produces no slots."* §7.3's
  `WorkerScheduleSection` carries the note *"No schedule yet - this worker materialises nothing until
  one is saved."* — that is the one place the product says this, and it is inside an edit card
  reached by a row action, not on the Setup screen.
- **The story**: *"they have never met the words template, horizon or materialised."* §7.3: those are
  the field labels — *Template*, *Horizon (days ahead kept generated)*, *Don't generate before* —
  alongside a worked arithmetic example sentence. The inventory records the field list; it does not
  record any first-run alternative, because there is none.
- **The inventory** (§7.3): `/calendar/workers`'s `PageHead` has **a title only** — no description
  sentence, unlike every chat screen. So does `/calendar/availability` (§7.6).

---

## 3.2 Re-cutting a schedule that already has bookings — `built`

### Surfaces

| Route | Inventory | Reached from |
|---|---|---|
| `/calendar/workers/:workerId/recut` | §7.5 | a **Re-cut** button in a Workers row — no nav entry |
| `/calendar/workers/:workerId/slots` | §7.4 | a **Slots** button in the same row, and a "View slots" link in the edit card |

### What the re-cut screen is

§7.5 — three sequential stages on one page, and **the only screen in the console that fetches nothing
on mount**:

1. A `Panel` with one *Re-cut from* date field and a **Preview** button.
2. The preview: one `Panel` per affected day, titled with the ISO date, containing a count of free
   slots that would be deleted and one row per booking — time range, service, customer, phone,
   status, and a **Cancel / Keep** radio pair, or *"Already happened as a no-show - cannot be
   cancelled, its day is kept."* A **Review & confirm** button, disabled until every booking has a
   decision, with the note *"Choose cancel or keep for every booking above before continuing."*
3. A confirmation `Panel` — a sentence with four bolded counts, a danger `Alert` *"This cannot be
   undone from this screen."*, and **Confirm re-cut** / **Back**.

Afterwards a "Done" `Panel` summarising days re-cut, days left untouched, slots deleted, slots
inserted and bookings cancelled, plus a list of the dates left in the old grid.

### What the story asks for, and what the screen already does

The story's three "must be able to"s are all present today: see before committing exactly what
breaks; decide **per booking**, not in bulk; and stop. This story is a **critique of a built screen**,
not a proposal.

### States this story requires that do not exist

- **The story**: *"Must not be made to choose blind between two lossy outcomes — today the system
  offers exactly two per affected day: cancel the booking, or leave the day in the old grid."*
  §7.5: the radio pair is exactly `Cancel` / `Keep`. There is no third option and no move.
  `flows.md` names `20-17`/`20-29` as what would make the trade less bad, and both are **planned**,
  not built.
- **The story**: *"When the primary goal fails — the world moved while they were deciding — that is
  an **expected** outcome, not an error. The person needs to be told **what changed**, not that
  something went wrong."* **The inventory** (§7.5): the screen's failure states are an `Alert
  tone="danger"` and *"No loading skeleton — the busy state is only a disabled button."* Nothing in
  §7.5 renders a diff of what changed.
- **The story**: *"Must never happen: a customer losing an appointment without the operator having
  seen that customer on screen and chosen it."* §7.5 shows customer and phone per booking row — but
  §7.1 records that the phone can render as the meta word *"hidden"* with a tooltip explaining a
  missing contact-visibility permission, and a tooltip is a native `title` that does not appear on
  touch (§12 / §10.9).

### Facts that bear on it

- §12.4 — this is the flow with a deadline in every row and no polling; the operator refreshes by
  hand.
- §7.5 — the preview renders **one `Panel` per affected day**, each containing a row per booking. A
  re-cut spanning a month is a very long page with no summary above it until stage 3.
- §7.1 — the queue's **Reject**, **Cancel** and **No-show** fire immediately with **no
  confirmation**, all three the same size, weight and variant (§12.3). The re-cut screen is
  three-stage and confirmed; the single-booking cancellation beside it is one click.

---

## 3.3 Booking somebody who called — `planned` (`20-28`)

### Surfaces

**None for this task.** The nearest existing screens, and why each is not it:

| Route | Inventory | Why it is not this |
|---|---|---|
| `/calendar` | §7.1 | the pending-bookings queue: read plus three destructive actions. No create |
| `/calendar/contacts` | §7.7 | read-only. Phone, Name, Notes, No-shows, First seen, Last seen. **No search, no filter, no pagination, and no drill-down to a customer's bookings** — the whole list renders at once |
| `/calendar/workers/:id/slots` | §7.4 | read-only. Seven columns; nothing on the screen is actionable |
| `/calendar/availability` | §7.6 | two write-only forms (Close a day, Change a day's hours) with **no calendar view, no month grid, and no list of days already closed** |

### Everything this story needs is absent

- no create-a-booking surface anywhere in the console
- no customer lookup by phone — `/calendar/contacts` has no search field (§7.7)
- no create-a-customer surface
- no whole-grid view: the closest is one worker's slots over a date range, as a table (§7.4)

### The one adjacent fact

§7.4's slot table has a **Status** column, and §12.8 records that three of its six labels are raw
enum identifiers: `PendingConfirmation`, `NoShow` and `Blocked` sit beside the translated
`Available`, `Booked` and `Cancelled`. Any surface that shows slot status inherits that vocabulary.

### Mobile note

The story sets the moment as *"with a customer on the phone… while still talking"*, and §10.4 applies:
a seven-column table on a phone is a side-scrolling region.

---

## 3.4 Recording what happened at the visit — `planned` (`20-23`)

### Surfaces

**None on the calendar side.** The analogous thing that exists is on the **chat** side:

| Surface | Gate | Inventory | What it is |
|---|---|---|---|
| Conversation outcome panel | `conversation:read`; setting needs `conversation:close` | §3.4 (5) | a single badge — Not recorded / Converted / Not converted / Follow-up needed — and three buttons to set it; the current one is `primary` and disabled |

Its standing note: *"Recorded by the operator - not a sale AGO Chat has independently verified."*

### What the story asks for that has no surface

- **The story**: *"record the outcome **and the takings** on the same card as the booking."* There is
  no takings, amount or money field anywhere in either product's interface. §5.2's conversion report
  counts outcomes, not values.
- **The story**: *"Must not be made to enter it anywhere other than where they already are."* A
  booking's own card does not exist: §7.1 is a queue row with three buttons, §7.4 is a read-only slot
  table. There is no booking detail screen.

### Facts that bear on it

- §5.4 — `/analytics/booking-flow` is the one screen relating chat to bookings. It renders a two-item
  `<dl>` ("Booking flows started", "Flows closed") and an `Alert tone="info"` carrying a
  three-sentence caveat that a closed flow is not a confirmed booking. It is **the only stat-figure
  treatment in the product**; every other number in every report is a table cell.
- `flows.md` leaves an **open question for the author** here — whether an outcome survives a moved
  appointment or belongs to the visit — and does not settle it. Nothing in the inventory bears on it,
  because neither surface exists.

---

## Cross-cutting facts from the inventory that touch every calendar story

- **§12.13** — on `/calendar/workers` the row actions are five same-size buttons: Edit, Schedule,
  Delete (danger), Slots, Re-cut. **Edit and Schedule call the identical handler.** A code comment
  says this is deliberate — "a named shortcut into the same place Edit opens".
- **§12.3** — worker deletion is confirmed by a **third `Panel` appended below the others**, not a
  `Dialog`. It is the only destructive confirmation in the product that is not a modal.
- **§12.12** — on `/calendar/setup`, the `Panel` titled "Approved page origins" carries the *embed*
  description ("Paste this on your own site…"). The embed snippet and the origins editor share one
  panel.
- **§13.1, corrected** — the inventory recorded the `/calendar/setup` embed snippet as broken four
  ways. That was filed as `22-22` and **fixed in `ago-console` at `a64fcac`**: the snippet now
  composes its URL from `apiBaseUrl`, emits `data-booking="true"`, and drops `data-booking-api`. The
  site key remains a deliberate placeholder because reading it needs `site:configure`, which this
  screen does not require; the copy now names where to get it and links to `/settings/install`. The
  backlog item is still marked *in review*. **`ui-inventory.md` §13.1 is stale on this point.**
