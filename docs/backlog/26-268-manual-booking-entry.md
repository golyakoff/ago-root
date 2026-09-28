# 26-268 · [design] Operator manual booking entry (mirror: console + android)

- **Stage**: 26. Kind: design proposal + recommended ticket breakdown (this file is the design; the
  slices below are filed as their own numbered items). Author need stated 2026-09-28.
- **Status**: proposed — not yet sliced into GitHub issues. This document is the research deliverable
  for the managing session to slice from.
- **Repos touched by the feature**: `ago-calendar` (the write), `ago-chat` (person/email registry
  contract), `ago-console` + `ago-android` (the two operator surfaces). No platform change.

## The need (author, verbatim intent)

A new AGO Calendar tenant already runs a business and has near-term bookings taken **outside** our
system (by phone). They must be able to **re-enter those by hand** so the slots are blocked and online
visitors can't double-book them. The operator enters a client by hand (name, phone; **email optional** —
hard to justify on a phone call and error-prone by ear), attaches that contact, picks an existing
**service** and an available **master**, and puts them on the calendar at a **date + time slot** — the
same axes a visitor picks, driven by the operator.

**UX constraints (honored, not re-litigated):**
- One entry point «Добавить вручную» inside Записи, opening a **dialog-style guided flow** like the
  visitor's own booking flow (name → phone → optional email → master → date → slot). Not a
  multi-screen chore across Clients/Записи.
- A manual booking is a **direct command against the calendar**, not a visitor chat: it must **not**
  create or pollute a chat conversation or message log.
- Keep it simple: one entry point, one guided form.

---

## 1. How the visitor flow works today, and what already exists to mirror

The booking write already anticipated this exact "operator path". `adr/0184` decision 2 and the
`26-208`/`adr/0187` operator reschedule (both merged) did most of the hard part.

**The atomic claim (the product's core concurrency guarantee).**
`Ago.Calendar.Domain/Event.cs` is one row that is both a free slot and the booking that took it. A
claim is a compare-and-set — `UPDATE events SET ... WHERE id = ANY(@ids) AND status = 'Available' AND
starts_at > @now` — whose rows-affected count *is* the verdict (rule 8). Overlap across rows is a GiST
exclusion constraint `ex_events_worker_no_overlap`. **A manual booking must block the slot through this
exact mechanism**; anything else re-introduces the double-book race the whole domain exists to prevent.

**Visitor write path** (`Ago.Calendar.Application/UseCases/BookEvent/BookEventHandler.cs`,
`POST /api/v1/calendars/{calendarId}/events/{eventId}/book` in
`Ago.Calendar.Api/Booking/BookingEndpoints.cs`): unauthenticated, resolves tenant from the calendar,
rate-limits per phone/calendar, resolves the run with `ConsecutiveRunFinder`, then claims via
`IBookingStore.TryBookAsync` into **PendingConfirmation** with a veto deadline. That public endpoint is
closed to everyone today by `PublicBookingApiGate` — irrelevant to us: the manual path is a **new,
operator-authenticated route**, not this one.

**The person model (crucial).** `adr/0184` removed the calendar's own `customers` copy. The calendar
now keeps only a thin `Ago.Calendar.Domain/PersonRecord.cs` (opaque person id + phone + verification
facts + no-show count). **The person's name is owned by AGO Chat.** For a booking with no chat origin,
`BookEventHandler` mints a person id locally (`IIdGenerator`), and the claim's transaction stages a
`PersonRegistered` outbox event (`Ago.Calendar.Contracts/PersonRegistered.cs`) carrying `PersonId`,
`AccountId`, `Phone`, `Name`. Chat consumes it in
`Ago.Chat.Application/UseCases/RegisterExternalPerson/RegisterExternalPersonHandler.cs` and creates a
`Visitor` + `VisitorContactDetail`s — **and nothing else**. This is the exact behaviour the manual path
reuses.

**The operator write path already exists** (`26-208`/`adr/0187`,
`Ago.Calendar.Application/UseCases/BookingLifecycle/RescheduleBookingHandler.cs` +
`Ago.Calendar.Application/Abstractions/IBookingRescheduleStore.cs`): an operator, gated on
`Permission.BookingReschedule`, claims a **new run straight into `Booked`** (skipping
PendingConfirmation) in one transaction via `IBookingRescheduleStore.TryReschedule`. This proves the
two facts the manual path needs: (a) an operator-authenticated claim exists, and (b) a slot can be
claimed **directly into `Booked`** with no veto window. Reschedule reuses an *existing* person; manual
entry differs only in that it **creates** one.

**The slot-picking UX already exists on both clients.** The console reschedule dialog
(`ago-console/src/pages/RescheduleBookingButton.tsx`, used from `CalendarBookingsPage.tsx`) picks a
date and loads the worker's day grid via `getWorkerSlots` (`GET /api/v1/console/workers/{id}/slots`,
`ago-console/src/api/calendarApi.ts:813`), then names the chosen start slot by its `eventId`. The
android mirror is `ago-android/.../bookings/RescheduleBookingScreen.kt` +
`core/network/.../bookings/KtorBookingsApi.kt` (`rescheduleBooking`, line ~410). **The manual dialog is
the reschedule dialog minus "which booking" and plus "who is the client".**

---

## 2. Permission gating — the recommendation

**A new `booking:create` permission is required; it does not exist today.** The calendar's local
`Ago.Calendar.Domain/Permission.cs` declares eight strings (`booking:confirm/reject/cancel/
mark_no_show/reschedule`, `customer:read/edit`, `calendar:configure`) — byte-for-byte the same eight in
`ago-chat/src/Ago.Chat.Domain/Permission.cs` (`22-05`/`adr/0093`: the account side owns the role
catalogue, the calendar reads grants through a projection; both `Permission.cs` files carry the "must
match byte-for-byte" comment on `BookingReschedule`). **The sync mechanism is manual and by wire
agreement, not a shared type** (`adr/0012`/`adr/0027`: separate repos, no `ProjectReference`). So adding
a permission means adding the identical `new("booking:create")` string in **both** `Permission.cs`
files, and granting it in `ago-chat`'s seeded roles (`RegisterSiteHandler.OperatorRolePermissions` /
`AdminRolePermissions`).

**Gate the manual-entry handler on `booking:create` AND `customer:edit`** (two `IPermissionChecker`
checks, the shape `MarkNoShowHandler`/`RescheduleBookingHandler` already use):
- `booking:create` — placing a booking on the calendar on a client's behalf.
- `customer:edit` — creating/attaching the client (name + phone) is a lead-card-write-shaped act;
  `customer:edit` is the permission `personal-data.md` already associates with writing customer
  identity.

This honors the author's "gate on capability, not role" reasoning: a **phone operator** gets a role
holding both, without needing Administrator. Seed **both** into the Operator and Admin roles so the
phone-operator scenario works out of the box (the Operator role today holds `customer:read`, not
`customer:edit` — see `CalendarBookingsPage.tsx` gating notes — so `customer:edit` must be added to it
for this feature).

> **Open sub-decision for the author (chat, not a ticket):** single `booking:create` (subsuming the
> contact creation, since the person is created via the same trusted server path a widget booking uses —
> which needs no permission at all) vs. the `booking:create` + `customer:edit` **pair** above. The pair
> is more granular (`adr/0016`) and matches the author's stated reasoning; the single permission is
> simpler to seed. Recommendation: the pair. Either way `booking:create` is new and must be added +
> seeded. **No backfill needed** while there are zero real tenants (re-confirm before relying on it);
> if tenants exist at build time, existing sites need a re-grant→projection pass
> (`reference_entitlement_backfill_to_existing_sites`).

---

## 3. The manual-entry write — Clean Architecture placement

### 3.1 Application (the use case)

New use case `Ago.Calendar.Application/UseCases/ManualBooking/` (sibling to `BookEvent/` and
`BookingLifecycle/`):
- `EnterManualBooking.cs` — command record: `OperatorId`, `TenantId`, `CalendarId`, `ServiceId`,
  `WorkerId`, `StartEventId` (the slot the operator picked, named by its grid `eventId` — same
  convention reschedule uses, never a wall-clock instant), `DisplayName`, `Phone` (raw string),
  `Email` (nullable).
- `EnterManualBookingHandler.cs` — composes what already exists:
  1. `IPermissionChecker` × 2 (`booking:create`, `customer:edit`) — first, so a caller with no right
     never learns whether anything exists (the ordering every lifecycle handler uses).
  2. Validate phone via `new PhoneNumber(...)` → rejection on `ArgumentException` (BookEventHandler's
     exact pattern). Email, if present, validated shape-only.
  3. Resolve calendar/worker/service/schedule; reject if the worker doesn't offer the service or either
     is inactive (BookEventHandler's checks verbatim).
  4. `ConsecutiveRunFinder.FindRun` over the worker's day grid (`events.ListForDayAsync`) to compute the
     run for the service's duration (courtesy read; rule 8 — availability is decided in the claim's
     `WHERE`).
  5. Mint a person id (`idGenerator.NewId(now)`) — **always new** for v1 (see §3.4).
  6. Call the new store port (§3.2), which claims straight into `Booked` + upserts the `PersonRecord` +
     stages the outbox events, in one transaction.

**Teaching note (placement):** the handler orchestrates; the transaction lives in the store
(Infrastructure), never in Application (`adr/0004`). This is the identical division
`RescheduleBookingHandler` + `IBookingRescheduleStore` already drew, and for the identical reason: a
write spanning a raw atomic claim **and** an EF/SQL person upsert **and** two staged outbox rows must
share one transaction, and "the transaction has to belong to something." The alternative — a new
`Event.EnterManually` domain method — is wrong: an aggregate sees only itself, cannot span the person
row and the slot row, and would re-implement preconditions that already exist. Composition in a use
case is the same call `adr/0187` made.

### 3.2 The store port + adapter

New port `Ago.Calendar.Application/Abstractions/IManualBookingStore.cs`:
`Task<BookingConfirmation?> TryEnterAsync(ManualBookingAttempt attempt, CancellationToken ct)`.
`ManualBookingAttempt` = `BookingAttempt` (`IBookingStore.cs`) **minus** `ConfirmationDeadline` (there
is no veto window) **plus** the outbox envelopes the handler built. Adapter in
`Ago.Calendar.Infrastructure.Postgres/ManualBookingStore.cs`, registered in
`ServiceCollectionExtensions.cs` + `CalendarModule.cs`.

In one transaction the adapter:
- Upserts the `person_records` row (phone, and — see §3.3 — `PhoneConfirmedByOperatorAt = now`), the
  same upsert `BookingStore` already does.
- Claims the run **straight into `Booked`** with the same `WHERE status='Available' AND starts_at>@now`
  compare-and-set the reschedule store uses (target status `Booked`, no deadline). Returns `null` on a
  lost race — an ordinary outcome, never a 500 (the `IBookingStore`/`IBookingRescheduleStore` posture).
- Stages `PersonRegistered` (the minted id → chat) and `BookingConfirmed` on the outbox, in the same
  transaction (rule 4).

**Teaching note (why a new port, not a flag on `IBookingStore`):** `IBookingStore.TryBookAsync` hard-codes
the claim into `PendingConfirmation`; the reschedule store hard-codes `Booked`. Each distinct
transactional shape got its own port rather than a `targetStatus` parameter — the same choice this
project already made once. A third port keeps the **hot, public** booking path's signature untouched,
lets manual entry stage a **different set of outbox events** (see §3.5), and carries its own gating
story. Alternative rejected: generalise `IBookingStore` with a target-status + optional-deadline — fewer
types, but it couples the contended public path to the operator path and muddies which events each
stages.

### 3.3 Phone handling

The operator is on a phone call with the client but has **not** proven number control via SMS. So this
is **not** a `PhoneVerifiedAt` (SMS-proof) fact. It **is** exactly `PersonRecord.PhoneConfirmedByOperatorAt`
— "I called and it is them" (`23-12`, already in the domain, set by `RecordOperatorConfirmedPhone`).
Recommendation: the manual store sets `PhoneConfirmedByOperatorAt = now`, leaves `PhoneVerifiedAt`
null. Minor; flag for the author. `RequiresVerifiedPhone` (the `BookEvent` gate) does not apply — the
manual path never runs through `BookEventHandler`'s verification gate.

### 3.4 Customer: always mint new for v1

`adr/0184` decision 2 mints a person id for a no-chat-origin booking; `adr/0147` is explicit that "a
phone is a hint, not proof" and nothing auto-merges two people who share a number. So v1 **mints a new
person every time** — the operator enters name+phone, a new contact is created and attached. This
matches "enter a client by hand… attach that contact." Picking an **existing** contact (dedup / "this
is a returning client") is a real enhancement but a **separate, later** decision (it reopens the
merge/identity question `adr/0184` deliberately simplified) — out of scope here, noted as a follow-up.

### 3.5 Outbox events

Stage exactly:
- `PersonRegistered` — the minted person → chat registry (creates the Person, **no conversation**).
- `BookingConfirmed` (`Ago.Calendar.Contracts/BookingConfirmed.cs`) — so downstream treats it like any
  confirmed booking (`20-05` SMS confirmation, analytics). Deliberately **not**
  `BookingPendingStateChanged` (it was never pending) — the same "stage exactly the right events"
  discipline `RescheduleBookingHandler` applies.

> **Analytics tie-in (see §7):** consider a booking-origin marker (`Online` / `OperatorManual`) so the
> funnel can distinguish manually-entered bookings. Cheapest form: an origin field on the anchor `Event`
> and on `BookingConfirmed`. Small, but a real contract choice — call it in the ADR.

### 3.6 API endpoint

New operator-authenticated route on the existing console group (`Ago.Calendar.Api/Configuration/
ConsoleEndpoints.cs`, `MapGroup("/api/v1/console").RequireAuthorization(OperatorPolicy)`):

`POST /api/v1/console/bookings/manual` → `EnterManualBookingHandler`. Body: `calendarId`, `serviceId`,
`workerId`, `startEventId`, `name`, `phone`, `email?`. It creates a resource, so `201` is defensible
(unlike the public `/book` which transitions an existing row and returns `200` — see
`BookingEndpoints.cs` remarks); return the new `bookingId` + slot span (`BookingConfirmedResponse`
shape). **Not** the public `/embed` or `/calendars/.../book` route.

**Reads reuse what exists — no new read endpoint.** The dialog needs: services + workers (from
`GET /api/v1/console/configuration`, which already returns services with `serviceIds` per worker) and
the worker's day grid (`GET /api/v1/console/workers/{workerId}/slots`, `getWorkerSlots`). The service's
run length is computed server-side at booking time (`ConsecutiveRunFinder`), exactly as reschedule does
— the dialog only names the **start** slot.

---

## 4. "Not in the chat log" — confirmed

A manual booking carries `OriginConversationId = null`. It stages `PersonRegistered`, which chat's
`RegisterExternalPersonHandler` turns into a `Visitor` + contact details **and nothing else — no
`Conversation`, no `Message`** (verified: that handler only calls `IPersonRegistrationStore`, assigns an
emoji pair, records phone/name/email details). The console confirmed-bookings page already renders **no**
"go to dialog" link when `originConversationId` is null (`CalendarBookingsPage.tsx` "dialog" column). So
the constraint holds by construction. **The place the visitor flow *does* create a conversation** is the
chat-originated booking path (`ChatModuleTask` / `ReplyToModuleTaskHandler`) — the manual path must never
route through that; it uses the new console endpoint, which has no chat coupling.

---

## 5. The two clients

### 5.1 Console (`ago-console`)
Entry point on `CalendarBookingsPage.tsx` (`/calendar/bookings`, the "confirmed bookings" screen where
reschedule already lives). Add «Добавить вручную» to the `PageHead` `aside` (beside Refresh), visible
when the operator holds `booking:create`. It opens a dialog modelled on `RescheduleBookingButton.tsx`:
1. Name (required) · Phone (required) · Email (optional).
2. Service select (from configuration) → Worker select (workers offering that service) → Date picker →
   slot grid via `getWorkerSlots` (reused verbatim).
3. Submit → new `createManualBooking(...)` in `calendarApi.ts` → `POST /bookings/manual` → on success
   `reload()`.
i18n both languages; page test + fixture; `npm run ux-gate` (Playwright — a DTO shape change can break a
stale fixture, `feedback_ago_console_full_command_set_includes_ux_gate`).

### 5.2 Android (`ago-android`)
Entry point on `ConfirmedBookingsScreen.kt` (the "Утверждены" segment of Записи —
`bookings/BookingsTab.kt`). Add «Добавить вручную» as a FAB or toolbar action, gated on `booking:create`.
It opens a guided bottom-sheet/step flow mirroring the console dialog and reusing the slot-picker built
for `RescheduleBookingScreen.kt`. Network: add `createManualBooking` to
`core/network/.../bookings/KtorBookingsApi.kt` (the `POST /bookings/manual` call, alongside
`rescheduleBooking`). **All new strings as resources, both languages** (`feedback_android_strings_must_be_resources`).
ViewModel + unit tests; the emoji-pair display for the created person is handled by chat's registration
(no android work).

---

## 6. ADR need — yes (draft core)

This clears the "decision worth arguing about" bar (`CLAUDE.md`): a new permission, a new booking-entry
origin that lands straight in `Booked` bypassing the confirmation window, and the mint-new-person /
event-staging choices. Draft **ADR-0188** (next free; highest is `0187`), landed in the same change as
the calendar backend slice:

- **Context**: onboarding tenants have external near-term bookings; operators must block those slots
  without the visitor's verify-and-confirm dance, and without creating a chat conversation.
- **Decision**: an operator-authenticated manual booking is a **new use case + `IManualBookingStore`
  port** that claims a run **straight into `Booked`** in one transaction, mints a new person
  (`PersonRegistered`), stages `BookingConfirmed`, sets `PhoneConfirmedByOperatorAt`, and is gated on
  `booking:create` + `customer:edit`. No veto window (the operator is the business). No dedup in v1.
- **Alternatives weighed**: (a) reuse `IBookingStore` with a target-status flag — rejected, couples the
  hot public path; (b) claim into `PendingConfirmation` then immediately `Confirm` — rejected, leaks a
  transient pending state and stages the wrong events; (c) a new `Event.EnterManually` domain method —
  rejected, cannot span the person + slot transaction (adr/0187's reasoning); (d) dedup against existing
  contacts by phone — deferred (`adr/0147`: a phone is a hint, not proof).
- **Consequences**: a booking-origin marker may be added for analytics (§3.5/§7); `booking:create` must
  be seeded and (if real tenants exist) backfilled.

---

## 7. Secondary proposal — post-slot outcome capture (lighter; to be fleshed out later)

When a slot finishes, the operator records the outcome for statistics/funnel: did the client **show up**,
was there a **purchase and how much**. Partial overlap already exists: `booking:mark_no_show` +
`EventStatus.NoShow` cover the "did not show" half (`Event.MarkNoShow`, `EventNoShowRecorded`,
`PersonRecord.NoShowCount` — though the counter increment is a known unbuilt gap, see
`MarkNoShowHandler` remarks). AGO analytics (`adr/0186`: ClickHouse raw store + `ago_analytics` rollups)
is where funnel/conversion lives.

**Shape to flesh out:**
- **Outcome states/fields** attached to the booking (the anchor `Event`, or a `booking_outcomes` table
  keyed by `bookingId`): `attended` (showed / no-show — reuse the existing `NoShow` status for the
  no-show case), `purchaseMade` (bool), `purchaseAmount` (`Ago.Calendar.Domain/Money.cs` already exists
  and `Service` already carries a price). A migration (calendar's migration lane).
- **Transition rules**: outcome recordable only after the slot has ended (mirror `Event.MarkNoShow`'s
  "not before `EndsAt`" invariant). A `Booked` visit becomes `Attended`(+optional purchase) or `NoShow`.
- **Permission**: a new `booking:record_outcome` (both products, byte-for-byte + seeded) rather than
  overloading `booking:mark_no_show`, for `adr/0016` granularity — flag single-vs-new to the author.
- **Analytics feed**: emit an outcome integration event through the outbox → the `adr/0186` ingest path
  → ClickHouse raw + hourly rollup into `ago_analytics`, giving the funnel booked → attended → purchased
  and revenue per service/master. Keep the calendar as publisher only (it already publishes; analytics
  owns the store).
- **UI**: an outcome control on **past** confirmed bookings in `CalendarBookingsPage` and the android
  `ConfirmedBookingsScreen` (only rows whose slot has ended). Mirror both.

This is a genuinely separate feature from manual entry (different permission, different tables, its own
analytics contract) and should get its own design/ADR pass when picked up — **not** bundled into the
manual-entry slices.

---

## 8. Recommended ticket breakdown (one ticket = one promise that lands green — rule 15)

### Manual entry (the primary feature)
1. **[cross-repo: ago-chat + ago-calendar] Add `booking:create` permission and seed it.** Add the
   identical `new("booking:create")` string to both `Permission.cs` files (byte-for-byte), grant it (and
   `customer:edit`, if the pair is chosen) in `ago-chat`'s seeded Operator + Admin roles
   (`RegisterSiteHandler`). One promise: the capability exists in both products and the right roles hold
   it. One worker owns the whole contract (`feedback_one_worker_per_cross_repo_task`). No backfill while
   zero real tenants.
2. **[ago-calendar] Manual-booking write + endpoint + ADR-0188.** `EnterManualBooking` use case,
   `IManualBookingStore` port + Postgres adapter (claim straight to `Booked` + person upsert + stage
   `PersonRegistered` & `BookingConfirmed`, one txn), `POST /api/v1/console/bookings/manual` gated on
   `booking:create` (+`customer:edit`), unit + integration tests, ADR-0188 in the same change. Ships
   with name + phone (email deferred to #3). One promise: an authenticated operator POSTs a manual
   booking and the slot lands `Booked` with no conversation. **Migration lane** (adds a column only if
   the origin marker is taken; otherwise no schema change).
3. **[cross-repo: ago-calendar + ago-chat] Carry optional email end-to-end.** Extend `PersonRegistered`
   (both wire copies, byte-for-byte) with `Email string?`; calendar passes it; `RegisterExternalPersonHandler`
   records an `Email` `VisitorContactDetail`. One promise: a manual booking's email reaches the person's
   contact channels. Separable because email is optional — #2 is green without it (extra JSON field is
   ignored by an un-updated consumer).
4. **[ago-console] «Добавить вручную» dialog.** On `CalendarBookingsPage`, gated on `booking:create`:
   name/phone/email + service/worker/date/slot picker (reuse `getWorkerSlots`) → `POST /bookings/manual`
   → reload. `createManualBooking` in `calendarApi.ts`, i18n both languages, page test + fixture,
   `typecheck && lint && test && ux-gate` green. One promise.
5. **[ago-android] «Добавить вручную» guided flow.** On `ConfirmedBookingsScreen` (Записи ▸ Утверждены),
   gated on `booking:create`: guided sheet mirroring the console, reusing the reschedule slot-picker;
   `createManualBooking` in `KtorBookingsApi`; string resources both languages; ViewModel + tests. One
   promise.

Order: #1 → #2 (needs the permission) → #3/#4/#5 in parallel (all consume #2's endpoint; #4/#5 include
the email field once #3's contract lands, or ship name+phone first and add the email field with #3).

### Outcome capture (secondary — file later, own design/ADR pass)
- O1 [ago-calendar] booking-outcome domain + fields + `RecordBookingOutcome` write + endpoint +
  migration (migration lane).
- O2 [cross-repo] `booking:record_outcome` permission (both products + seed).
- O3 [ago-analytics/ago-calendar] outcome integration event → `adr/0186` pipeline → funnel rollups.
- O4 [ago-console] + O5 [ago-android] outcome-capture UI on ended bookings (mirror).

---

## 9. Deviations from the author's sketch (with reasoning)

- **Backlog number**: filed as **26-268**. 26-267 was already taken by the reserve-me.ru → agochat.ru
  domain migration (referenced by number across many merged ago-deploy/ago-android commits, tracked in
  ago-business rather than a public issue), so this feature takes the next free number, 26-268.
- **`booking:create` is genuinely new** — it is not among the eight synced permissions today. Confirmed
  against both `Permission.cs` files.
- **No new operator "open slots" read endpoint** — the sketch implies mirroring the visitor slot flow,
  but the operator already has `getWorkerSlots` (used by reschedule) which returns exactly the day grid
  the dialog needs; adding a second read would duplicate it.
- **Email is a chat concern, not a calendar one** — the calendar keeps no name/email (`adr/0184`); email
  flows through `PersonRegistered` to chat's contact-detail model (which already has an `Email` kind).
  Hence email is its own cross-repo slice (#3), separable from the core write (#2).
- **Straight-to-`Booked`, no veto window** — a manual booking is the operator asserting a booking that
  already happened by phone; the confirmation window exists to let the business veto a *visitor's*
  request, which is meaningless here.
