# 26-175 — Booking-lifecycle operator actions (design)

Status: **design / scoping**. No production code, no tickets filed by this pass. Issue
`golyakoff/ago-root#1685`.

The author's request (2026-09-26): rework the operator actions on a booking.

- **Pending («Ожидают») detail sheet:** remove «Отменить» (the general cancel); add **«Подтвердить»**
  (a manual operator confirm). Final action pair: **Подтвердить + Отклонить**.
- **Confirmed («Утверждены») detail sheet:** add **«Отменить»** (cancel) and **«Перенести
  оператором»** (operator reschedule of this one booking). **«Не пришёл»** stays (post-visit,
  `Booked`-only).

This document establishes the current truth from the code first, then designs the two genuinely new
capabilities — an operator-facing **Confirm** and a per-booking **Reschedule** — and states exactly
which actions each sheet carries after the change.

---

## 1. Current truth (read from the code, not assumed)

### 1.1 The domain state machine — `ago-calendar` `Ago.Calendar.Domain/Event.cs`

One row is both the free slot and the booking that took it. The transitions that exist today:

| Transition | Method | Reason recorded | Caller(s) |
|---|---|---|---|
| `Available → PendingConfirmation` | `Claim` | — | `BookEventHandler` → `IBookingStore.TryBookAsync` (atomic claim) |
| `PendingConfirmation → Booked` | `Confirm` | — | **`ExpiredBookingConfirmer` (the auto-confirm sweep) ONLY** |
| `PendingConfirmation → Cancelled` | `Reject` | `RejectedByOperator` | `RejectBookingHandler` |
| `PendingConfirmation \| Booked → Cancelled` | `Cancel` | `CancelledByOperator` | `CancelBookingHandler`, `RecutConfirmHandler` |
| `Booked → NoShow` | `MarkNoShow` | — | `MarkNoShowHandler` |
| `Available → Blocked` | `Block` | — | day-editing |

Confirmed facts, each verified in this pass:

- **`Confirm` has no operator-facing endpoint.** Its only caller is the sweep
  (`ExpiredBookingConfirmer.ConfirmExpiredAsync`). `ConsoleEndpoints.cs` maps exactly three booking
  transitions: `reject`, `cancel`, `no-show`. There is no `confirm` route.
- **`Event.Confirm` was deliberately built to accept an early operator confirm.** Its own doc comment:
  "Both real callers are legitimate on either side of [the deadline]: `20-04`'s sweep confirms rows
  whose window has closed, and an operator who is looking at the request right now may confirm it
  immediately rather than wait." So the aggregate already supports manual confirm — only the
  Application use case, the endpoint, and the wiring are missing.
- **`Permission.BookingConfirm` (`booking:confirm`) is declared but unused.** No handler checks it. The
  console already treats it as a real operator permission — `CalendarQueuePage` gates on
  `hasAnyBookingActionPermission` = `booking:confirm`/`reject`/`cancel`, and the seeded Operator role
  (in `ago-chat`'s `RegisterSiteHandler.OperatorRolePermissions`) already **grants** `booking:confirm`.
  So the permission and its grant exist end-to-end; nothing consumes it yet.

### 1.2 The auto-confirm model

A claim sets `ConfirmationDeadline = now + ConfirmationWindow` (`BookingOptions.ConfirmationWindow`,
default **15 minutes** — app config, not per-tenant today). The sweep confirms every
`PendingConfirmation` row whose `confirmation_deadline <= now`, oldest first, one transaction per tick,
`SKIP LOCKED` per booking anchor. On confirm it stages, **once per booking** (from the anchor):

- `BookingConfirmed` (the eventual `20-05` SMS contract; no consumer built yet), and
- `BookingPendingStateChanged("Booked")` (console fan-out — `Ago.Calendar.Worker` pushes every
  connected operator a bare "re-read the queue" signal).

"Всё подтверждается автоматически" is the product's headline promise: the customer is told they are
booked immediately; the operator has the window to veto. Manual Confirm must **coexist** with this, not
replace it — the operator accepts early; the sweep stays the fallback for everything nobody touches.

### 1.3 There is no per-booking reschedule today

- `RecutSchedule` (`RecutConfirmHandler`) recuts a **worker's whole schedule** over a date range:
  it re-materialises days and, per the operator's per-booking Keep/Cancel decisions, cancels bookings
  through the ordinary `CancelBookingHandler`. It is not a move of one booking to a new time.
- `Event.Cancel`'s doc comment — "the product spec rules out **customer-initiated** cancellation and
  rescheduling outright" — refers to the *customer* being unable to reschedule. It is **not** a
  statement that an operator reschedule exists or is designed. Operator reschedule is a genuinely new
  capability.
- `CancelBookingHandler`'s remarks already record the open question this reschedule inherits: **a
  cancelled slot is not re-offered** — `Event` has no transition back to `Available`, and the
  materialiser only fills days with no rows at all (`adr/0053`). "Whether a cancellation should re-open
  the slot is a real product question and it is still nobody's yet."

### 1.4 Where the actions live in the UI today

| Surface | Pending («Ожидают») | Confirmed («Утверждены») |
|---|---|---|
| **Android** `PendingBookingsScreen.kt` / `ConfirmedBookingsScreen.kt` | detail sheet: **Отклонить + Отменить** + the «Подтвердится через N ч» countdown line | detail sheet: **Перейти к диалогу + Закрыть** only |
| **Console** `CalendarQueuePage.tsx` / `CalendarBookingsPage.tsx` | table row: **Отклонить + Отменить + Не пришёл** (inline) | **read-only** — no action buttons at all |

Notable current-truth gaps this rework touches:

- **«Не пришёл» is not an operator action on Android at all today.** `markNoShow` exists in the API
  layer, but no Android sheet wires a no-show button; `WorkerSlotsScreen` shows `NoShow` only as a
  status *label*. The author's "«Не пришёл» stays" is therefore, on Android, effectively "«Не пришёл»
  **arrives**, on the confirmed sheet, where it belongs."
- **The console offers «Не пришёл» on the *pending* queue** — a row the server refuses it for
  (`Event.MarkNoShow` requires `Booked`). `26-163` already called this out for Android and removed it
  there. This rework should also move no-show off the console's pending queue.
- The mockup site `booking.html` §04 already *draws* «Подтвердить»/«Отклонить» on the pending list
  cards — an earlier design intent that `26-163` could not implement because no confirm endpoint
  existed. This item makes that intent real.

---

## 2. Revised state machine

No new **states** and no new domain transition *method* is strictly required. The two new capabilities
are expressed with transitions that already exist on the aggregate:

- **Manual Confirm** = `Event.Confirm` (`PendingConfirmation → Booked`) called from a new operator
  use case, instead of from the sweep alone.
- **Reschedule** = `Event.Cancel` on the old run (`Booked → Cancelled`, reason
  `CancelledByOperator`) **plus** `Event.Claim`/atomic-claim on a fresh run at the new time
  (`Available → PendingConfirmation`, then immediately `Confirm → Booked`), committed in one
  transaction.

```
                         Claim (visitor)
        Available ───────────────────────────▶ PendingConfirmation
           ▲                                      │   │   │
           │ (no transition back — by design)     │   │   │
           │                          Confirm ────┘   │   └──── Reject  ──▶ Cancelled
           │                    (sweep OR operator)   │              (RejectedByOperator)
           │                                          ▼
           │                                        Booked
           │                                          │  │  │
           │                    MarkNoShow ───────────┘  │  └──── Cancel ──▶ Cancelled
           │                    (post-visit)             │           (CancelledByOperator)
           │                                             │
           │          Reschedule (operator) = Cancel old run  ┐
           └───────── new run claimed at target time ─────────┘  (atomic, one txn)
                      Available(new) → PendingConfirmation → Booked
```

The only judgment call: reschedule as **cancel-old + claim-new** rather than an in-place mutation. See
§4.1 — it is forced by this data model, not chosen for convenience, and it is the subject of a proposed
ADR.

---

## 3. New capability A — operator Confirm

### 3.1 Endpoint and use case

- `POST /api/v1/console/bookings/{bookingId}/confirm` on `ConsoleEndpoints`, mirroring the
  reject/cancel/no-show maps (204 on success, problem on failure).
- New `ConfirmBookingHandler` (Application, `UseCases/BookingLifecycle/`), the same shape as
  `RejectBookingHandler`:
  1. permission check — `Permission.BookingConfirm`;
  2. load by id, tenant-guard (`booking.TenantId != command.TenantId` → wrong tenant);
  3. resolve the whole run by `BookingId` (`ListByBookingIdAsync`);
  4. `slot.Confirm(now)` on every row (load-mutate-save; `xmin` protects the group);
  5. stage outbox rows **once per booking, from the anchor**, reusing the sweep's mappers verbatim:
     `BookingConfirmedMapper.ToEnvelope(anchorConfirmed, …, groupEndsAt)` and
     `BookingPendingStateChangedMapper.ToEnvelope(anchorId, tenant, "Booked", now, …)`. This keeps a
     **single confirmation contract** regardless of who confirmed — the eventual SMS consumer cannot
     tell (and must not care) whether the sweep or an operator confirmed.

**Teaching note (layering).** The confirm decision is an Application use case, not an Infrastructure
one, because it is uncontended single-actor work: one operator, load-mutate-save, `Event.Confirm`
enforcing the state precondition. That is exactly the division `IBookingStore`'s remarks draw — the
*claim* is raw atomic SQL because it is contended and racy; the operator transitions
(`Reject`/`Cancel`/`MarkNoShow`, and now `Confirm`) are ordinary aggregate writes. The alternative —
folding confirm into the sweep's `ExpiredBookingConfirmer` — would put an operator-triggered,
request-scoped action inside a background-job adapter, and couple a console endpoint to
`AgoCalendarDbContext` raw Npgsql it has no reason to touch.

### 3.2 Interaction with auto-confirm

- Manual confirm moves the row to `Booked` and **clears `ConfirmationDeadline`** (via `Event.Confirm`).
  The sweep's predicate (`status = 'PendingConfirmation'`) then never matches it again. No double
  confirm is possible.
- **The race is already-solved.** If an operator confirms in the same instant the sweep claims the
  anchor: whoever commits first wins. If the sweep wins, the operator's save is rejected by `xmin`
  (`EventConcurrencyConflictException` → "the booking changed under you"). If the operator wins, the
  sweep's `FOR UPDATE ... WHERE status='PendingConfirmation'` simply returns zero rows for that
  booking. This is byte-for-byte the race `RejectBookingHandler` already documents. No new lock.
- **Auto-confirm stays the fallback.** Nothing about adding manual confirm changes the sweep. A booking
  nobody touches still auto-confirms at its deadline.

### 3.3 Does manual Confirm skip the veto window?

**Yes — recommended.** The veto window exists to give the operator time to *decide*. An operator who
presses «Подтвердить» **has** decided; leaving a residual window open afterwards would be incoherent
(what would a later auto-confirm add to an already-`Booked` row? nothing — the row is already out of
`PendingConfirmation`). Manual confirm finalises immediately. This is a product question (§6 Q4) only
because the author should ratify it, not because the code leaves a choice — `Event.Confirm` clears the
deadline unconditionally.

### 3.4 Notifications

Manual confirm stages the identical `BookingConfirmed` the sweep stages, so whatever the future
`20-05` SMS consumer does on auto-confirm, it does on manual confirm too — one code path, one message.
No new contract. `BookingPendingStateChanged("Booked")` drives the existing console/queue re-read.

---

## 4. New capability B — per-booking operator Reschedule

### 4.1 Shape: cancel-old + claim-new, one transaction (proposed ADR)

Given the data model (one row = one slot = the booking; a booking is a run sharing a `BookingId`
anchor; the no-overlap GiST constraint; the materialiser only fills empty days; **no transition back
to `Available`**), an **in-place move** (mutating `StartsAt`/`EndsAt`/`LocalDate` on the existing rows)
is architecturally wrong:

- the target time already exists as its own `Available` grid rows — moving onto it would double the
  rows for that interval, or fight the GiST exclusion constraint;
- the vacated original interval would have to become bookable again, which is exactly the
  "no transition back to `Available`" the aggregate deliberately does not offer;
- it desyncs the materialised grid from `MaterializeFrom`/`RecutFrom` bookkeeping.

So reschedule **is** what the model already means by moving a booking: **release the old run, claim a
new run.** Concretely, in one transaction:

1. resolve the old run by `BookingId`; verify it is `Booked` (or `PendingConfirmation` — see Q-scope)
   and belongs to the tenant;
2. compute the new run at the target start via `ConsecutiveRunFinder` over the target day's grid, using
   the **same worker** and **same service** (so slot length / buffer / run length are unchanged);
3. **claim the new run atomically** — the same compare-and-set `IBookingStore` uses:
   `UPDATE events SET … WHERE id = ANY(@newIds) AND status='Available' AND starts_at > @now`, requiring
   rows-affected `= @newIds.Length`. If the target was taken in the race, rows-affected differs, the
   whole transaction rolls back, and the reschedule fails with "slot no longer available" — **the old
   booking stays `Booked`, untouched**;
4. `Cancel` the old run (`Booked → Cancelled`, `CancelledByOperator`);
5. the new run lands directly in **`Booked`** (an operator moving an appointment is the confirmation
   authority — see §4.3), carrying the same `PersonId`, `ServiceId`, `OriginConversationId`, and phone;
6. stage outbox (see §4.4).

**This needs a new port** — call it `IBookingRescheduleStore.TryRescheduleAsync` — because the cancel
(EF load-mutate-save) and the claim (raw atomic `UPDATE`) must share one transaction, and no existing
port spans both. This is the exact precedent `ExpiredBookingConfirmer` sets (raw Npgsql claim + EF
transition on one connection, one transaction) and the exact reasoning `IBookingStore`'s "one port
rather than two" paragraph gives: the transaction spanning both statements has to belong to something.

**Rule 8 compliance (non-negotiable):** the new-slot availability is a write decision, so it is decided
by the claim's own `WHERE` clause **inside the write transaction** — never pre-read, never cached. A
courtesy read via `ConsecutiveRunFinder` (like `BookEventHandler`'s) only decides *which ids to ask the
claim for*; a stale answer there costs nothing more than the ordinary "slot no longer available"
rejection.

**Concurrency:** the cancel-half races the sweep exactly as `CancelBookingHandler` does (it already
accepts `Booked`); the claim-half races other bookers exactly as `BookEventHandler` does. Both are
already-solved patterns; composing them in one transaction adds no new race, only the requirement that
they commit together.

**Proposed ADR:** "Per-booking operator reschedule is cancel-old + claim-new in one transaction, not
an in-place move." This is a decision between real alternatives that changes a guarantee (booking
identity changes across a reschedule — see §4.5), so it qualifies for an ADR under the
project's own rule. **This pass proposes the ADR; it does not write it.**

### 4.2 Same worker / same service, or changeable? (recommended: time-only for v1)

Recommend v1 = **same worker, same service — a pure time move.** Rationale:

- run-length computation stays identical (same service duration, same worker schedule);
- no need to re-validate a new worker×service offering, worker-active, or cross-calendar movement;
- "different worker or different service" is genuinely "cancel this and make a new booking," which the
  product can already express (cancel + the booking flow) and which can be a later, separate item.

This is a product question (§6 Q1) — the author may want same-worker/different-time only, or
also-different-worker. The recommendation keeps v1 small and the atomic claim trivially correct.

### 4.3 New run's confirmation state (recommended: straight to `Booked`)

When an operator reschedules, the new run should land **directly in `Booked`**, not back in
`PendingConfirmation` with a fresh veto window. The operator is deliberately placing the appointment;
a veto window (time for the operator to change their mind) is meaningless for an action the operator
just took. This is consistent with §3.3 (manual confirm skips the window). Product question §6 Q4
covers both.

### 4.4 Notifications

The honest position, matching the existing posture (`RejectBookingHandler`: "staging a contract nobody
reads would be a guess"):

- **Do not** invent a customer-facing `BookingRescheduled` contract in this item while there is no
  consumer. When the `20-05` notification work is built, a reschedule should tell the client "your
  appointment moved from X to Y" — a dedicated `BookingRescheduled(oldSlot, newSlot, person, tenant)`
  event is the right shape then (cleaner for the SMS than a Cancelled+Confirmed pair a consumer must
  correlate). Record it as the design intent; build it with the consumer.
- **Console live-refresh gap (pre-existing, noted not fixed):** the confirmed-bookings view (Android
  «Утверждены», console `CalendarBookingsPage`) has **no realtime push today** — it is a date-range
  read. So a reschedule/cancel of a `Booked` item will not live-update the confirmed view regardless of
  this item; only a manual refresh / re-read shows it. `BookingPendingStateChanged` only fires for
  pending transitions. Making the confirmed view live is out of scope here and should be its own item
  if the author wants it.

This is product question §6 Q2 (notify the client) and §6 Q3 (cancel+rebook vs in-place — answered by
§4.1: it is cancel+rebook at the data level, presented as a single "move" action).

### 4.5 The freed old slot (recommended: keep current behaviour, file the standing question)

Reschedule inherits `CancelBookingHandler`'s existing behaviour: the old run becomes `Cancelled` and is
**not** re-offered as `Available`. The time frees up only in the sense that the no-overlap constraint
stops covering it; nothing re-materialises a slot there. This is identical to what a plain cancel does
today, so reschedule introduces no new inconsistency. Whether cancel/reschedule should re-open the
freed slot for other customers is a **real standing product decision** that applies equally to plain
cancel — it should get its own number, not be smuggled into this item (§6 Q5).

### 4.6 Permission (recommended: new `booking:reschedule`)

Reschedule is a distinct act from cancel — `adr/0016`'s granularity argument (already invoked to split
`booking:reject` from `booking:cancel`) applies: a tenant may want a senior operator to move an
appointment but not a junior one, independently of who may cancel. Recommend a new
`Permission.BookingReschedule = "booking:reschedule"`.

**Cross-repo cost (flag):** per `adr/0093`, calendar permissions must match `ago-chat`'s catalogue
byte-for-byte, are granted on the account side, and read here through the role-assignment projection.
A new `booking:reschedule` therefore requires: (a) add it to `Ago.Chat.Domain.Permission`; (b) add it
to the seeded Operator role in `RegisterSiteHandler.OperatorRolePermissions` (and any role catalogue /
console role-editor UI); (c) declare it in `Ago.Calendar.Domain.Permission`. If the author prefers to
avoid a new permission for v1, the fallback is to gate reschedule on the existing `booking:cancel`
(defensible — reschedule *contains* a cancel) at the cost of losing the independent grant. Product
question §6 Q6.

---

## 5. Actions per sheet after the change

### 5.1 Pending («Ожидают») — `PendingConfirmation`

| Before | After |
|---|---|
| Отклонить (`Reject`) | **Отклонить** (`Reject`) — unchanged |
| Отменить (`Cancel`) | **removed** |
| — | **Подтвердить** (`Confirm`, new) — primary |
| «Подтвердится через N ч» countdown line | **kept** — the auto-confirm fallback, still true |

Rationale for removing «Отменить» from pending: on a row that auto-confirms if left alone, the coherent
negative action is **veto** (`Reject`), not the confirmed-visit `Cancel`. The two landed on the same
`Cancelled` status but mean different things to the customer; a pending row's rejection is the veto.
Keeping both was the redundancy `26-163` inherited. Final pair: **Подтвердить + Отклонить.**

### 5.2 Confirmed («Утверждены») — `Booked`

| Before | After |
|---|---|
| Перейти к диалогу | **Перейти к диалогу** — kept |
| Закрыть | **Закрыть** — kept |
| — | **Отменить** (`Cancel`, new on this sheet) — danger tone |
| — | **Перенести оператором** (`Reschedule`, new) |
| — (no-show absent on Android) | **Не пришёл** (`MarkNoShow`) — shown/enabled only when the visit's slot has ended (`now >= EndsAt`); `Booked`-only |

«Не пришёл» gating: `Event.MarkNoShow` refuses before `EndsAt`. The sheet should only surface (or only
enable) it once the slot has ended, so the button is never offered where the server refuses it — the
lesson `26-163` applied to the pending queue, applied here.

### 5.3 Console parity

- `CalendarQueuePage` (pending): remove «Отменить» and «Не пришёл» from the row; add «Подтвердить».
  Final: Подтвердить + Отклонить. (`booking:confirm` is already granted to the Operator role.)
- `CalendarBookingsPage` (confirmed, currently read-only): add row actions Отменить / Перенести /
  Не пришёл (no-show gated on slot-ended), matching the Android confirmed sheet. The reschedule picker
  on a wide console screen can be a slot-picker inline; on Android it is the flow sketched in §6 of the
  mockup.

---

## 6. Consolidated product questions (with recommendations)

See the session report for the same list; repeated here so the doc stands alone.

1. **Reschedule scope — same worker/service, or changeable?** *Rec:* v1 = same worker + same service,
   time-only move. Different worker/service = cancel + new booking, a later item.
2. **Notify the client on reschedule?** *Rec:* yes, when `20-05` notifications exist; do not stage a
   consumer-less contract now. Design intent = a `BookingRescheduled(old,new)` event built with its
   consumer.
3. **Reschedule = cancel+rebook, or in-place move?** *Rec:* cancel-old + claim-new in one transaction
   (forced by the data model; §4.1). Presented to the operator as one "move" action; a new booking id
   under the hood (§4.5 / Q on identity).
4. **Does manual Confirm (and reschedule's new run) skip the veto window entirely?** *Rec:* yes —
   confirming/placing is the decision; the run goes straight to `Booked`, deadline cleared.
5. **What happens to the freed slot on reschedule/cancel?** *Rec:* keep current behaviour (not
   re-offered), and file "should cancel/reschedule re-open the slot" as its own standing decision — it
   applies to plain cancel too.
6. **Permissions for confirm and reschedule.** Confirm → reuse existing `booking:confirm` (already
   declared + granted, unused). Reschedule → *Rec:* new `booking:reschedule` (adr/0016 granularity),
   which costs a matching entry in `ago-chat`'s catalogue + Operator-role seed (adr/0093); fallback is
   to gate on `booking:cancel`.

Two smaller ratifications worth a yes/no:

7. **Reschedule a still-`PendingConfirmation` booking, or `Booked` only?** *Rec:* `Booked` only for v1
   (a pending booking is more naturally rejected + rebooked). Keeps the confirmed sheet the single home
   for reschedule.
8. **Move «Не пришёл» off the console pending queue** (it is refused there today). *Rec:* yes — same
   fix `26-163` made on Android.

---

## 7. Proposed implementation-ticket breakdown

One promise each (rule 15). Provisional numbers — the managing session assigns real ones (next free
~26-176+). Repo-tagged. Dependencies noted. **Migration flag:** none of these require a schema change
if reschedule keeps the current "cancelled row, new claimed rows" model (no new column) — reschedule
reuses existing columns. The only migration risk is if the author later wants a persisted
reschedule/cancellation *reason* column, which is out of scope here.

| # (prov.) | Repo | Promise (one thing) | Depends on |
|---|---|---|---|
| A | **calendar** | Operator Confirm: `ConfirmBookingHandler` + `POST /bookings/{id}/confirm`, gated on `booking:confirm`, staging the sweep's two contracts from the anchor. | — |
| B | **calendar** | (if a new permission is chosen) add `booking:reschedule` to the calendar `Permission` catalogue. | ties to C-chat |
| C-chat | **chat** | add `booking:reschedule` to `Ago.Chat.Domain.Permission` **and** the seeded Operator role. *(One cross-repo pairing with B — dispatch as one worker covering both repos.)* | — |
| D | **calendar** | Per-booking reschedule: `IBookingRescheduleStore` + adapter (cancel-old + claim-new, one txn, rule 8) + `RescheduleBookingHandler` + `POST /bookings/{id}/reschedule`. Requires the ADR (E) decided first. | A (confirm path reused for new run → Booked), ADR E, permission B/C |
| E | **ago-root** | ADR: "per-booking operator reschedule = cancel-old + claim-new in one transaction, not in-place." *(Decision, not code — the author ratifies; write with adr-writer.)* | — |
| F | **android** | Pending sheet: replace Отклонить+Отменить with **Подтвердить + Отклонить**; wire confirm API; keep countdown. New string resources both languages. | A |
| G | **android** | Confirmed sheet: add **Отменить** + **Не пришёл** (gated on slot-ended); wire cancel + no-show APIs. New strings. | (uses existing cancel/no-show endpoints) |
| H | **android** | Confirmed sheet: add **Перенести оператором** + the reschedule slot-pick flow; wire reschedule API. New strings. | D, G |
| I | **console** | `CalendarQueuePage`: remove Отменить + Не пришёл from pending rows, add Подтвердить (Подтвердить + Отклонить). | A |
| J | **console** | `CalendarBookingsPage`: add Отменить / Не пришёл (slot-ended gated) / Перенести to the confirmed view. | D |
| K | **mockup** | `ago-android-design` `booking.html` §04: the reworked pending sheet, confirmed sheet, and reschedule-flow sketch. **(This item's own mockup deliverable — likely landed with this design pass.)** | — |

Ordering: E (ADR) and A (confirm) unblock most of it. B+C (permission, one cross-repo worker) precede
D. The reschedule store D is the one non-trivial backend slice. Android F/G can proceed as soon as A
and the existing endpoints are in; H waits on D.

**No migration lane needed** on current scope. If Q (persisted reason column) is later answered "yes,"
that single item goes to the migration lane on its own.
