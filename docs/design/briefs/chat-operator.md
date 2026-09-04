# Brief — chat operator

A join between `flows.md` and `ui-inventory.md`. **Nothing here is new judgement.** Section
references are to `ui-inventory.md`; story numbers are `flows.md`'s.

---

## The role, as `flows.md` states it

**Wants**: to do the work without friction, and to be judged on something they recognise as fair.
**The product wants**: the work to be comfortable to do and **uncomfortable to fake** — built as
*the honest path is the easy path* and *the work is visible*, never as surveillance.

## Every surface this role can reach

| Route | Name | Gate | Inventory |
|---|---|---|---|
| `/` | Conversations — the queue with nothing open | session only | §3.1, §3.2 |
| `/conversations/:conversationId` | The open conversation | session only | §3.3 |
| — | The visitor aside's six panels | each gated on `conversation:read` | §3.4 |
| — | Shortcuts dialog, Alerts dialog | ungated, off the rail | §3.5 |

Everything else in the console is behind `site:configure`, `site:erase` or `calendar:configure`. A
plain operator's navigation is **one item**: "Conversations" (§1, the nav table). The other twenty
are not drawn.

## The frame these two routes live in

§3.0. A CSS grid, `grid-template-columns: 21rem minmax(0, 1fr) 18rem`, areas `rail main aside`. These
two routes are the **only** ones in the console that pass `fixed` (`height: 100dvh`, regions scroll
internally, the page does not).

## Mobile constraints that apply to every story below

From §10 and §11. `flows.md` 2.1 sets the moment explicitly: *"Sometimes on a phone, because in a
small shop the operator is also the owner and is cutting hair."*

- **39rem — 624px — of width is committed before the conversation gets any**, in the two fixed grid
  tracks.
- **≤ 74rem (~1180px)**: the aside loses its column and becomes a strip *above* the thread; its
  closing note is `display: none`.
- **≤ 52.5rem (~840px)**: one column; **the shell stops being viewport-height**
  (`.ago-shell--fixed { height: auto }`); the rail is hidden **whenever a conversation is open**, and
  a `← Conversations` link appears. The thread gets `max-height: 60vh` so the composer stays
  reachable. **This is the only place in the console where the navigation model changes rather than
  the column widths** — list and conversation become alternating full-width views joined by one back
  link.
- Consequently, **the composer is not pinned to the bottom on a phone**: it sits in document flow
  after a 60vh-tall thread.
- **≤ 40rem**: the composer's action row stacks below the textarea. The stylesheet records why:
  measured **28.5px of textarea at a 375px viewport**, wrapping text one character per line.
- **≤ 40rem**: the 21-item nav bar is `display: none` and the hamburger + drawer replace it (§1). The
  drawer is a native `<dialog>` with real focus trapping, covered by `ux-gate/mobileNavDrawer.spec.ts`.
- Hover-only affordances: `a.ago-list__row:hover` and `.ago-table tbody tr:hover` (§10.9).

---

## 2.1 Knowing what needs them right now — `built`

### Surfaces

| Route/surface | Inventory | What is on it |
|---|---|---|
| The rail | §3.1 | uppercase label + `ConnectionStateBadge`; two ghost buttons (**Alerts**, **Shortcuts**); an unhealthy-link `Alert`; a tag-filter `Select` (only when the site has tags); queue-load error; a transient announcement; then two sections |
| Section "Assigned to me" | §3.1 | whole-row `NavLink`s: brand mono badge with the visitor id's **first 8 hex**, optional accent "New", optional danger unread count, and `Open 14m` (ticking every 10s) |
| Section "Waiting" | §3.1 | `<li>` with `.ago-list__row--static`: sunken surface, dashed border, default cursor, **no anchor, no hover response** |
| `/` | §3.2 | `.ago-empty-state` — a `⌘` glyph, "Pick a conversation", and a paragraph ending *"nothing here needs claiming"* |

### States it has

Loading = a `Skeleton` per section (3 lines / 2 lines). Empty = per section, `.ago-empty`:
"Nothing assigned yet. New conversations arrive here automatically." / "Nothing waiting." Error = one
`Alert` above the list. The queue polls every 15s and refreshes on a realtime assignment event. The
document title carries the unread count.

Realtime link, five states, rendered as a dot badge whose label is one of `Live` / `Connecting…` /
`Reconnecting…` / `Server restarting` / `Offline` — **the full explanatory sentence is in its `title`
attribute only**, which does not appear on touch.

### States this story requires that do not exist

- **The story**: *"Must be able to … act on a waiting conversation — **which today is impossible**."*
  **The inventory** confirms it three times: §3.1 (the waiting row is deliberately not a control),
  §4.1 (`/admin` rows are not links — no cell and no row navigates to a conversation), §4.2
  (`/search` shows a Waiting result with the note *"Unclaimed — assign it from the queue to open
  it"*, pointing at a queue that has no assign action). §13.13 records this as one fact: **no claim,
  assign or take-control action exists anywhere in the product.**
- **The story**: *"see at a glance what is unanswered, what is mine, and what is going stale."* The
  rail has "Assigned to me" and "Waiting" and an elapsed time per row. There is no *stale* state, no
  threshold styling, and no sort control (§3.1: rows are `oldestFirst`, fixed).
- **The story**: *"Must not be made to rely on a number that flickers."* Nothing in §3.1 marks a
  count as provisional or settling; the unread badge renders whatever the last poll returned.

### Facts that bear on it

- §12.9 — the row's identity is `visitorId.slice(0, 8)` in a mono badge. There is no visitor name
  anywhere in the product.
- §12.10 — "Conversations" is the nav label for `/`, the rail's own heading, and half of "All
  conversations" for `/admin`; the mobile back link says "← Conversations" while every
  permission-refusal page says "Back to queue" and points at the same route.

---

## 2.2 Holding a conversation — `built`

### Surfaces

| Surface | Inventory | What is on it |
|---|---|---|
| Conversation header | §3.3 | `← Conversations` (below 52.5rem only), `Conversation with <first 8 hex>` — or the bare fallback "Conversation" when the summary is not in the queue — and a small ghost **Close conversation** (only with `conversation:close`) |
| Thread | §3.3 | day separators, two-tone bubbles, author in words on the first message of a run, a `<time>` clock per bubble, absolute timestamp + sequence in the `title` |
| Composer | §3.3 | auto-growing textarea, **Attach**, **Suggest a reply**, **Send**, a hint line, an in-flow canned-response picker on `/`, drag-and-drop over the whole composer |
| Visitor presence | §3.4 (1) | a badge — `Online` / `Offline` / `Presence unknown` — polled every 10s |

### States it has

Hub not connected (a `role="status"` line, thread and composer still rendered) · join failed (a
danger `Alert`, **and the composer is removed entirely**) · closed (composer replaced by an info
`Alert`) · send failed or unconfirmed (a danger `Alert` above the composer quoting the failed body,
with a **Retry** action) · locating a searched message (a spinner at the top of the thread).

Closing is a two-step `Dialog` with **six distinct failure messages** mapped by `closeOutcome.ts`
(network, already closed, concurrency conflict, not found, reassigned, no permission); retryable
failures relabel the confirm button to "Try again".

### States this story requires that do not exist

- **The story**: *"Must be able to see … whether their last message was delivered."* **The
  inventory** (§3.3): *"No per-message delivery state. Operator bubbles show a timestamp; there is no
  sent / delivered / read indicator anywhere."* Failure is reported once, for the whole composer, not
  per message.
- **The story**: *"Must be able to see … whether anyone else is on this conversation."* Nothing in
  §3.3 or §3.4 shows a second operator. The `/admin` table has an "Assigned operator" column (§4.1)
  and the conversation screen does not.
- **The story**: *"Must not be made to lose a half-typed reply when they are pulled away."* §3.3: the
  draft is component state; navigating away and back re-mounts the page and clears it (the effect on
  `conversationId` change resets `draft`, `pendingAttachment`, `uploadError` and the rest).
- **The story**: *"How we know it worked. The proportion of conversations with two operators replying
  within the same minute."* No surface records or shows this.

### Facts that bear on it

- §3.3 — the thread has **no empty state**: a conversation with no messages renders an empty `<ol>`.
- §3.3 — the *join failed* state is the only one that removes the composer; on a phone that leaves a
  header, an alert and an empty region.

---

## 2.3 One person arriving through several channels — `partial`

### Surfaces

| Surface | Gate | Inventory | What is on it |
|---|---|---|---|
| "Linked channels" aside panel | `conversation:read`; Prefer needs `conversation:send`; Unlink needs `channel_identity:unlink` | §3.4 (6) | rows of a `kind` badge + mono address + optional "Preferred" badge, with Prefer / Clear and Unlink; below, a `Select` of linkable kinds and a **Generate code** button; the generated code appears in a success `Alert` as plain text |
| "Previous conversations" aside panel | `conversation:read` | §3.4 (2) | the visitor's earlier conversations, opening read-only in a `Dialog` |
| The aside's closing note | — | §3.4 | states in words that earlier conversations appear "when this visitor has been recognized on a channel such as MAX, Telegram or SMS" |

### States it has

Skeleton · danger alert · `.ago-empty` "No channels linked yet." · rows · a success alert carrying a
generated code · an action error.

### States this story requires that do not exist

- **The story**: *"Must be able to see the person rather than the channel."* **The inventory**
  (§12.7): `ChannelIdentitiesPanel.tsx` renders `<Badge>{identity.kind}</Badge>` — the **raw server
  enum** — and its picker's `<option>`s are the raw kinds too, while `/analytics` has translated
  channel names (`analyticsChannelSms`, `analyticsChannelMax`, `analyticsChannelTelegram`,
  `analyticsChannelWhatsApp`). The same concept is named two ways in two screens.
- **The story**: *"Must not be made to work it out from an identifier."* §3.4 (1): the aside's facts
  block is four mono identifiers — full visitor id, conversation start, site id, conversation id —
  "wrapped rather than truncated so they can be copied whole".
- **The story**: *"the visitor must not be made to repeat themselves across channels."* Nothing on
  the visitor's side surfaces a cross-channel history (§9).
- **The inventory** (§3.4): all six aside panels are gated on `conversation:read` and render
  **nothing at all** without it — so an operator without that grant sees the facts block, a silent
  gap, then the closing note. `flows.md`'s own trap applies: *absent and forbidden look identical.*

---

## 2.4 Being measured — `partial`

### Surfaces

| Route | Gate | Inventory | Relevant content |
|---|---|---|---|
| `/analytics` | `site:configure` | §5.1 | a **By operator** table: operator, Conversations, Avg. first response, Avg. duration, Missed |
| `/analytics/conversion` | `site:configure` | §5.2 | a **By operator** table: Converted, Not converted, Follow-up needed, Not recorded, Conversion rate |
| Conversation outcome panel | `conversation:read`; setting needs `conversation:close` | §3.4 (5) | the operator's own act of recording an outcome |

### The central fact

**An ordinary chat operator cannot reach either report.** Both are gated on `site:configure`, which
is the tenant-admin grant (§1, the nav table). The story's *"Must be able to see their own numbers,
the same ones their tenant sees, **first**"* has no surface: there is no operator-scoped view of
anything, and no route in `App.tsx` between "the queue" and "the whole site".

### States those reports have

Checking permissions · denied · loading (`Skeleton lines={4}`) · overall-count-zero
(`.ago-empty` "No conversations in this range.") · per-table empties, each with its own sentence
("No conversations attribute to an operator in this range.") · error, with a distinct message for an
inverted range.

### States this story requires that do not exist

- **Per-operator scope.** No route, no filter, no self view.
- **The story**: *"Must not be made to compete on things outside their control: who was online when
  the hard conversation arrived, or which visitor happened to be easy."* §5.1: the By-operator table
  cuts the same five columns as every other table on the page, with no shift, load or difficulty
  dimension.
- **The story**: *"Must never happen: a metric an operator first learns about from their manager."*
  §12.9: the operator column is `operatorId.slice(0, 8)` in mono — *"the reports name operators the
  reader cannot identify"*, which `flows.md` 4.4 also records. An operator cannot find their own row.
- **The story**: *"Whether operators can predict their own numbers before seeing them."* §5.1–§5.4:
  **none of the four report screens contains a chart, sparkline, trend arrow or any graphical
  element.** Every number is a table cell, and there is no comparison to a previous period.

### Facts that bear on it

- §5.1 vs §5.2 — `/analytics` has **no date presets**; `/analytics/conversion` and `/analytics/tags`
  have three (This month / Last month / Last 30 days). The same two screens label their fields
  **From** / **To** while the other two say **From (optional)** / **To (optional)** (§12.6).
- §3.4 (5) — the outcome panel carries the standing note *"Recorded by the operator - not a sale AGO
  Chat has independently verified."*

---

## 2.5 Going offline — `partial`

### Surfaces

| Route | Who | Inventory | Notes |
|---|---|---|---|
| `/settings/auto-reply` | tenant admin (`site:configure`) | §6.4 | configured **per site**, not per operator |
| The rail's connection badge | operator | §3.1 | reports the hub connection, not a deliberate act |
| Alerts dialog | operator | §3.5 | Desktop notifications and Sound — receiving, not availability |

### The central fact

`flows.md`: *"Offline auto-reply is configured **per site, not per operator**, so the operator's own
act of leaving has no representation at all."* The inventory agrees from the other side: there is no
presence, status or availability control anywhere in the operator's surfaces (§3.1–§3.5), and the
only presence in the product is the **visitor's**, polled every 10s and shown in the aside
(§3.4 (1)).

### States this story requires that do not exist

- No route, control or state for "I am leaving".
- **The story**: *"so that visitors are told the truth and my colleagues know."* Neither half has a
  surface: the widget's status line carries connection state only (§9.5), and no console screen shows
  which operators are online.
- **The story**: *"Must not be made to just close the tab and hope — which is what happens when the
  act has no surface."* §3.1's link states include `Offline`, but that is the browser's connection
  to the hub, not the person's availability. The two are named the same word in the same product.

### The one adjacent fact

§3.5 — the Alerts dialog's intro states *"Both are off until you turn them on, and neither fires for
the conversation you already have open on a visible tab."* That is the only place the console
acknowledges the operator is sometimes not watching.
