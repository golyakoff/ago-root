# 26-112 · Записи list — real names + reachable contact, and a two-way dialog ⇄ booking link — design & scoping

- **Stage**: 26 (Android app)
- **Kind**: design/scoping pass. No production code. Deliverables: this spec, a refined mockup
  (`assets/26-112-bookings-refined-mockup.html`), and a proposed implementation-ticket breakdown
  (§7) + product questions (§6) for the author to approve.
- **Item**: `docs/backlog/26-112-design-bookings-show-names-contacts-and-dialog-booking-navigation.md`
- **Sibling in flight**: `docs/design/26-111-thread-contact-detail-panel.md` — the in-dialog
  contact-detail bottom sheet. §5 states the boundary between the two so the contact/phone reveal does
  not diverge.
- **Author's overriding principle**: the mockup is the agreed target — "make it convenient; we build
  it." Where the real API cannot deliver a mockup element, this doc proposes the concrete additive API
  change (repo / endpoint / DTO / field / migration), never a "skip it because the API lacks it."

---

## 0. The headline finding (read this first)

The confirmed-bookings payload **already carries the customer's name and phone**. The Записи list shows
no name **not because the wire lacks it, but because the name is never collected when a booking is
made**, so the column is almost always null.

- `Ago.Calendar.Contracts.ConfirmedBookingResponse` carries `CustomerDisplayName`, `CustomerId`,
  `Phone` and `Masked` on every row (`ConsoleContracts.cs:202`). The read store populates them from
  `customers.display_name` / `customers.phone` (`ConfirmedBookingReadStore.cs:41-43`).
- The Android row **already renders** `customerDisplayName` when non-null, falling back to
  `IdentifierText(customerId)` (`ConfirmedBookingsScreen.kt:196-210`). `IdentifierText` renders
  `shortId(id)` — the first 8 hex chars of the GUID (`ui/components/IdentifierText.kt`). **That is the
  `7c4e18f0` the author boxed in red.** The web console shows the same null-name state as
  «не записано» (`CalendarBookingsPage.tsx:256`).
- `customers.display_name` is null for essentially every booking because **no booking-creation path
  collects a name**:
  - The **chat-driven** booking flow (`ReplyToModuleTaskHandler`) books with `DisplayName: null`
    (`ReplyToModuleTaskHandler.cs:411`); its step machine is service → worker → date → slot → phone →
    complete (`ChatBookingTaskState.cs`), with **no name step at all**.
  - The **widget/public** booking (`BookEventRequest`) accepts an *optional* `DisplayName`
    (`BookEventRequest.cs:27`) but the flow does not require or collect one.
  - The **chat→calendar contact carryover** (`ContactCollectedCustomerStore.cs`) writes only
    `phone` / `source` / `source_contact_id` — it never sets `display_name`, even though AGO Chat *does*
    hold the visitor's typed name as a `VisitorContactDetailKind.Name` row (`25-62`).

So the name plumbing from request → `customers.display_name` → payload → row **already exists end to
end** (`BookEvent.DisplayName` → `BookingAttempt` → customer upsert → read store → contract → Android
row). The single missing link is **collecting the name at booking time and making it mandatory**, which
is exactly the author's ask #1.

The «Сова · Клубника» emoji pair the item quotes is AGO **Chat's** visitor handle (`VisitorEmojiPair`,
`visitorEmojiNames`), *not* a calendar field — the calendar confirmed-booking row has no emoji identity.
Today the calendar row can only ever show a real name or the hex `shortId`. The refined mockup shows the
real name and never the hex.

**The two genuine, cross-cutting gaps are:** (A) name is not collected/required at booking creation, and
(C) nothing links a booking to the conversation it was created in, in either direction. Everything the
author asked about the phone (ask #3) needs **no API change** — the fields are already on the wire and
an audited reveal endpoint already exists; it is an Android-surfacing job.

---

## 1. Element-by-element map (mockup slot → real data source today)

"Android client" = whether `ago-android` already has the field/adapter. **GAP-x** cross-references §2.

| # | Mockup slot | Backend source today | Android today | Status |
|---|---|---|---|---|
| R1 | Row start time (10:00) | `ConfirmedBookingResponse.StartsAt` | `ConfirmedBooking.startsAt` (26-51) | **EXISTS** |
| R2 | Service title (Стрижка) | `ConfirmedBookingResponse.ServiceName` (nullable) | `ConfirmedBooking.serviceName` | **EXISTS** |
| R3 | **Client-name slot (red box)** | `ConfirmedBookingResponse.CustomerDisplayName` — **almost always null today because no flow collects a name** | `ConfirmedBooking.customerDisplayName`, rendered; null → `shortId` hex | **PARTIAL — payload/render exist; the datum is empty. GAP-A** |
| R4 | Duration («60 мин») | derived from `StartsAt`/`EndsAt` | derived on-device | **EXISTS** |
| R5 | Row → view contact / phone (ask #3) | `Phone` + `Masked` already on payload; reveal `POST /api/v1/console/contacts/{customerId}/reveal-phone` exists (`26-53`) | `ConfirmedBooking` **drops** `phone`/`masked` (26-51 scoping); `BookingsApi.revealCustomerPhone` **already implemented** | **PARTIAL — backend complete; Android carries neither field nor a detail surface. GAP-B (Android-only)** |
| R6 | Row → jump to originating dialog (ask #4a) | **no field ties a booking to a conversation** | none | **GAP-C1** |
| G1 | Master group header + count («ИРИНА СОКОЛОВА · 4 записи») | server order `order by local_date, w.display_name, min(starts_at)`; grouped client-side (`groupByDayThenWorker`) | `groupByDayThenWorker` + `WorkerGroupHeader` (26-51) | **EXISTS** |
| G2 | Day strip with per-day dots | `LocalDate`/`Weekday` per row; strip derived | `ConfirmedBookingsStripDay` + `ConfirmedDateStrip` (26-51) | **EXISTS** |
| G3 | Tabs «Ожидают (2) \| Утверждены \| Клиенты» | pending/confirmed/contacts reads | `BookingsTab` (26-48/51/52) | **EXISTS** |
| D1 | In-dialog booking chip → jump to Записи→Утверждены at this booking (ask #4b) | chat `ModuleTask` has `ConversationId` + `ExternalTaskId`; **no resulting `bookingId` recorded** | none | **GAP-C2** |

### Already true (so no ticket rebuilds it)
Master grouping, the day strip + dots, the three tabs, the confirmed read, the pending read, the
contacts read, **and the audited calendar phone-reveal** (`revealCustomerPhone`, `26-53`) all exist and
ship. The name column, the phone fields, and the row-tap detail surface are all rendered-or-plumbed
already; the work is data collection (GAP-A), Android surfacing (GAP-B), and the link (GAP-C).

---

## 2. Gaps — and the concrete additive change that closes each (no "skip it")

### GAP-A — the client-name slot (R3): the name is never collected, so `display_name` is null

The datum has a column (`customers.display_name`), a request field (`BookEvent.DisplayName` /
`BookEventRequest.DisplayName`), a read-store projection, a contract field, and a rendered Android/console
slot — **all already present**. The only missing thing is a booking-creation step that *asks for the
name and requires it*. The author's ask #1: "booking creation now REQUIRES a name and a mandatory phone."

Two independent writers must start supplying a name; both are additive (no new column):

- **A1 — chat-driven flow (ago-calendar).** Add a name round to the chat booking task: a new
  `ChatBookingTaskState.AwaitingName` and a `ChatBookingTask.ChooseName(...)`, sent as a
  `form` primitive (the same primitive the phone step already uses — `ModuleStepFactory.PhoneForm`), then
  passed as `BookEvent.DisplayName` instead of the hard-coded `null` at
  `ReplyToModuleTaskHandler.cs:411`. Ordering (name before or after phone) is **Q3**. **Size: M.** No
  migration (`ChatBookingTask` stores state; add `Phone`-style nullable `DisplayName` field — the
  table already round-trips nullable strings, but confirm whether a column is needed → likely a small
  migration on `chat_booking_tasks`; if so it takes the migration lane).
  *Teaching note:* the name belongs on `ChatBookingTask` (chat-orchestration state), not on `Event` or
  `Customer` — the same "which primitive was last sent and what has been picked in *this* exchange"
  reasoning that aggregate's own doc comment gives for keeping `Phone` there rather than on the booking.

- **A2 — widget/public flow (ago-calendar + ago-widget).** Make `DisplayName` **required** in the public
  booking surface: add a mandatory name field to the widget booking form and validate it server-side in
  `BookEventHandler` (today it is `string?` and unenforced). Because this changes a public contract from
  optional-to-required, it wants a line in `api-design.md` and is a deliberate decision (Q3/Q5).
  **Size: M** (widget form field + handler validation + tests).

- **A3 — retroactive carryover (ago-calendar, optional).** AGO Chat already collects the visitor's typed
  name (`VisitorContactDetailKind.Name`), but `ContactCollected` carries only one kind/value per event
  and the carryover keys on phone, so the name never reaches `customers.display_name`. If the author
  wants existing chat contacts' names to populate, extend the carryover to also apply a `Name`-kind
  value to the matching customer. **Size: M**, and it is a *separate* convenience from A1/A2 — governed
  by Q6. Not required to satisfy ask #1 (A1+A2 do that for all *new* bookings).

- **A4 — the fallback when a name is genuinely absent (ago-android).** Even after A1/A2, legacy rows and
  any operator-created booking with a blank name will have `customerDisplayName == null`. The row must
  **never** show the hex `shortId` as the primary identity again. Fallback order (Q1): masked phone
  (already on the payload once GAP-B lands) → localized emoji-pair label *if* one is ever carried →
  a plain «Без имени» label. **Size: S** (Android render + one string), rides GAP-B.

*Teaching note:* none of A1–A4 is "the API lacks the name." The API has always been able to carry it.
The failure was a flow that collected a phone and nothing else, so the most useful field on the screen
was structurally always empty. The fix is at the point of collection, not the wire.

### GAP-B — view the contact / phone from a booking (R5, ask #3): Android-only, no API change

`ConfirmedBookingResponse` already carries `Phone` + `Masked` on every row, and
`POST /api/v1/console/contacts/{customerId}/reveal-phone` is the audited reveal, **already implemented in
Android's `KtorBookingsApi.revealCustomerPhone`** (`26-53`). The confirmed booking already carries
`customerId`, which is the reveal key. What is missing is purely on the Android client:

- **B1** — carry `phone` + `masked` onto the `ConfirmedBooking` domain type + wire DTO (they are
  currently omitted by 26-51's deliberate reduction). **Size: S.**
- **B2** — a **booking-detail bottom sheet** opened by tapping a row: name, service, time, master,
  duration, and the phone with a «Показать» reveal reusing the exact `RevealPhoneResult`
  (`Revealed/Refused/Failed`) shape and the `revealCustomerPhone` endpoint keyed by the booking's
  `customerId`, with `surface = "AndroidBookings"` (a new reveal-surface label; see §5 for coherence
  with 26-111). **Size: M.** Whether the phone is inline on the list row or only behind the sheet is
  **Q2**.

No backend or migration work. The reveal audit trail (`IContactPhoneRevealRepository`) is the same one
every other calendar reveal writes; only the `surface` string differs.

### GAP-C — the two-way dialog ⇄ booking link (ask #4): a real gap in both directions

Today the pieces exist but are **deliberately kept opaque to each other** and neither side stores the
other's id as a queryable fact:

- Chat side: `ModuleTask` carries `ConversationId` **and** `ExternalTaskId` (= the calendar
  `ChatBookingTask.Id`) (`ModuleTask.cs:22,28`). So *chat* can map an external task id → conversation.
- Calendar side: `ChatBookingTask` **explicitly discards** the `conversationId` chat sends —
  "accepted … only long enough to be handed back unread on the next call; they are never stored here"
  (`ChatBookingTask.cs:22-25`, honouring `adr/0065` guard 2). The resulting `Event`/booking carries no
  conversation reference. And the confirmed-booking payload carries no task id.

So there is **no stored edge** from a confirmed booking back to its conversation, and **no stored edge**
from a conversation forward to its resulting `bookingId`. Both directions need one additive, opaque id —
and this is a decision worth an **ADR** because it amends `adr/0065` guard 2 (calendar deliberately not
retaining chat's conversation id).

#### C1 — booking → dialog (ask #4a)

**Proposed (ago-calendar):** store the `conversationId` chat already sends as an **opaque string** on the
booking, and echo it on the confirmed-booking payload.

- Persist it on `ChatBookingTask` (opaque, un-interpreted — exactly the arms-length treatment
  `Operator.ExternalSubjectId` gets), and carry it onto the `Event`/booking rows at claim time so the
  read store can join it.
- Add nullable `OriginConversationId : string?` to `ConfirmedBookingResponse` (null for a booking not
  created from a chat — e.g. an operator-entered or widget booking).
- **Migration:** a nullable `origin_conversation_id` column on the booking/events (calendar migration
  lane, one migration). **Contract change** is additive/nullable. **ADR** amending `adr/0065` guard 2 to
  "stored, opaque, never interpreted." **Size: M–L** (domain + claim write + read-store join + contract +
  migration + ADR + tests).
- **Android:** carry `originConversationId` onto `ConfirmedBooking`; when non-null the detail sheet (B2)
  shows a «Перейти к диалогу» affordance that opens the thread by that conversation id (reusing the
  existing thread navigation). When null, the affordance is absent (Q4). **Size: S** on top of B2.

*Teaching note:* storing an opaque conversation id on the calendar side does **not** make the calendar
product depend on the chat product — it never dereferences it, exactly as it never dereferences a
Keycloak `sub`. The platform-vs-product rule is about code/package references, and there are none here;
the string is data. That is precisely why an ADR is the right place to record the reversal of `adr/0065`
guard 2 — it is a deliberate, reasoned change to a guarantee, not a layering breach.

#### C2 — dialog → booking (ask #4b)

**Proposed (ago-chat):** record the resulting `bookingId` on the chat side when the booking completes, so
the in-dialog booking chip can deep-link into Записи → Утверждены at that booking.

- When the module returns its terminal `confirmation_card`, have the module wire carry the resulting
  `bookingId` (calendar already knows it — `BookingConfirmation`), and store it on the chat `ModuleTask`
  as a new nullable `ResultBookingId : string` (opaque to chat, same discipline as `ExternalTaskId`).
- **Migration:** nullable `result_booking_id` on `module_tasks` (chat migration lane, one migration).
  **Wire:** the module confirmation step gains an opaque `bookingId` field. **Size: M** (module wire +
  `ModuleTask.RecordResult(...)` + persistence + migration + tests).
- **Android/chat transcript:** the in-dialog booking chip/step, when it carries a `bookingId`, shows a
  «Открыть запись» affordance that navigates to Записи → Утверждены, selects the booking's
  `localDate` in the day strip, and scrolls/highlights that booking row. Requires the confirmed-bookings
  screen to accept a "focus this bookingId" navigation argument. **Size: M** on Android.

Whether C2 is worth its cost for v1, or whether one direction (C1, booking → dialog) is enough to ship
first, is **Q7**.

---

## 3. How the name is displayed in the row (the red-boxed slot)

Decided shape (mockup §"refinement"), independent of the product questions:

- **Primary line = the real name**, bold, `titleMedium` — the first thing an operator scans, paired with
  the start time on the right (the existing `ConfirmedBookingRow` two-line shape, unchanged).
- **The hex `shortId` is never the primary identity again.** When `customerDisplayName` is null the row
  falls back per **Q1** — preferred: the masked phone (a real, recognizable fact) with «Без имени» as
  the last resort — never the raw GUID prefix.
- **Second line = service · duration**, unchanged.
- Optional, low-emphasis: a small phone glyph/áffordance at the row's trailing edge signalling "contact
  reachable here" that opens the detail sheet (B2). Whether the phone shows inline vs only in the sheet
  is **Q2**; the mockup shows it behind a tap to keep the list scannable.

The emoji-pair handle is **not** drawn (the item says emoji icons need not be in the mockup, and the
calendar row has no emoji identity anyway).

---

## 4. The two-way navigation design (summary)

- **From a confirmed booking → the dialog** (C1): row tap → booking-detail sheet → «Перейти к диалогу»
  (shown only when `originConversationId` is present) → opens that conversation's thread.
- **From an in-dialog booking chip → the booking** (C2): the transcript's booking step, once it carries
  a `bookingId`, shows «Открыть запись» → opens Записи → Утверждены, selects the booking's day, and
  focuses the row.
- **The empty case** (a booking with no linked dialog — an operator-entered or widget booking) is real
  and expected; the affordance is simply absent, not an error (Q4).

---

## 5. Boundary with 26-111 (contact/phone reveal must stay coherent)

26-111 designs the **in-dialog** contact-detail bottom sheet; 26-112 designs the **Записи** list and the
booking-detail sheet. Both reveal a masked phone, and they must feel identical without being wired
identically:

- **Same UX + same result vocabulary.** Both use the «Показать» control, the `RevealPhoneResult`
  (`Revealed/Refused/Failed`) shape, "server sends the unmasked value, never unmasked client-side," and
  masked-stays-on-failure. 26-111 reuses this *pattern* (its doc §3, C2); 26-112 reuses the *actual
  implemented* calendar reveal client.
- **Different endpoints, on purpose — and that is correct.** A conversation's contact detail is chat
  data, revealed via `POST /api/v1/conversations/{id}/contact-details/{id}/reveal` (chat,
  `conversation:read`). A confirmed booking's phone is calendar data, revealed via
  `POST /api/v1/console/contacts/{customerId}/reveal-phone` (calendar, `customer:read`). The two products
  keep separate audit trails (`IContactPhoneRevealRepository` on each side) — collapsing them would be a
  product-boundary breach. The booking sheet uses the **calendar** endpoint keyed by the booking's own
  `customerId`; the thread sheet uses the **chat** endpoint. They share the component and the copy, not
  the wire.
- **`surface` label distinguishes them in the audit.** 26-111's thread reveal and 26-112's booking reveal
  pass distinct `surface` strings (e.g. `AndroidThread` vs `AndroidBookings`) so the reveal log stays
  answerable ("where was this number revealed from").

State the boundary explicitly in both implementations so a later reader does not "unify" the two reveals
and cross the product line.

---

## 6. Product questions (not decided here — CLAUDE.md rule 14 "file as the question")

**Q1 — name-slot fallback when `customerDisplayName` is null.**
- *A (preferred)* — masked phone → «Без имени». Cost: **S**, rides GAP-B (needs the phone on the row).
- *B* — «Без имени» only. Cost: **0**, but throws away a real, recognizable fact the payload already has.
- *C* — keep the hex `shortId`. Cost: **0**, but this is exactly what the author rejected.
Never the raw GUID as primary identity. Recommendation to weigh: A.

**Q2 — phone on the list row: inline or behind the detail sheet?**
- *A (mockup)* — behind a row tap → detail sheet with «Показать». Keeps the list scannable; one reveal
  per deliberate open. Cost: the sheet (B2).
- *B* — masked phone inline on every row with an inline «Показать». More reveals, noisier list, but one
  fewer tap. Cost: inline reveal state per row (the console does this on its table).
Recommendation to weigh: A for a phone screen.

**Q3 — when is the name collected, and in what order vs the phone?**
- Chat flow: a name round before phone, after phone, or a single combined form? Cost: a new
  `AwaitingName` state either way; combined form is one fewer round-trip but a bigger `form` primitive.
- Widget flow: name field required (A2). Confirm the author wants the *public* contract to make it
  mandatory (a real optional→required contract change).

**Q4 — a booking with no linked dialog (operator-entered / widget booking).**
Affordance simply absent (recommended), or a disabled/explained state? Absent is honest and matches "not
every booking came from a chat." Cost: 0 either way.

**Q5 — does making the widget name mandatory risk abandonment?** Requiring a name before a public visitor
can book raises friction. Option: mandatory everywhere (author's stated intent) vs mandatory only in the
operator/console-created path and optional in the public widget. Cost: a validation branch. This is a
conversion-vs-data-quality product call, not a technical one.

**Q6 — retroactively carry over already-collected chat names (A3)?** AGO Chat already holds many visitors'
typed names; A3 would populate `display_name` for existing chat-sourced customers. Cost: **M**, and it
touches the carryover path + personal-data doc. Or leave history as-is and only fix new bookings (A1/A2).

**Q7 — ship both link directions now, or C1 (booking → dialog) first?** C1 alone already delivers the
most-asked jump (from a booking on the operator's Записи screen to the conversation). C2 (dialog →
booking) needs a chat migration + module-wire change + a focus-a-row navigation on the list. Cost: C2 is
roughly a second M-ticket set. Ship C1 first, C2 as a fast-follow?

**Q8 — master-first vs time-first grouping / day strip.** The mockup keeps master-grouped + day-selected
(already shipped). Confirm this stays the shape (recommended — it is what the author drew) rather than a
flat time-ordered agenda. Cost: 0 to keep; a re-layout to change.

---

## 7. Proposed implementation-ticket breakdown

Each is one promise that lands green (rule 15). **Not filed here — proposed for the author to approve;
numbers are provisional.** Repo tags: **[calendar]**, **[chat]**, **[widget]**, **[android]**.

> **Numbering caution:** the sibling `26-111` design doc provisionally proposed `26-112`…`26-128` for
> *its own* implementation tickets, which collides with this item's own number and range. The author must
> deconflict both proposals into one numbering when filing. The numbers below use a distinct provisional
> band (`26-150`+) to avoid clashing on paper; they are placeholders.

**Data collection — the name (GAP-A):**

- **26-150 [calendar] — collect a mandatory name in the chat booking flow (A1).** New
  `ChatBookingTaskState.AwaitingName` + `ChatBookingTask.ChooseName` + a name `form` step; book with the
  collected name instead of `DisplayName: null`. Green = a chat-driven booking lands with a non-null
  `customers.display_name`. *Migration lane if a `chat_booking_tasks` column is needed. Depends on: none.*
- **26-151 [calendar + widget] — require a name in the public/widget booking (A2).** Widget form field +
  `BookEventHandler` validation making `DisplayName` required; `api-design.md` note. Green = a widget
  booking without a name is refused; with one, `display_name` is set. *Depends on: none. Gated on Q5.*
- **26-152 [calendar] — carry over already-collected chat names (A3).** Extend the contact carryover to
  apply a `Name`-kind value to the matching customer's `display_name`; personal-data doc line. Green =
  an existing chat contact with a typed name shows that name on its next confirmed booking. *Depends on:
  none. Gated on Q6 — optional.*

**Surface the phone from a booking (GAP-B, Android-only):**

- **26-153 [android] — carry `phone` + `masked` onto `ConfirmedBooking` (B1).** Add the two fields to the
  domain type + wire DTO (already on the server). Green = adapter maps them; unit-tested. *Depends on:
  none.*
- **26-154 [android] — booking-detail bottom sheet with phone reveal (B2).** Row tap → sheet (name,
  service, time, master, duration, masked phone + «Показать» via `revealCustomerPhone`,
  `surface="AndroidBookings"`). Green = sheet opens, reveal replaces the masked number in place.
  *Depends on: 26-153.*
- **26-155 [android] — name-slot fallback (A4).** Null name → masked phone → «Без имени»; never the hex.
  Green = a null-name row shows the fallback, never `shortId`. *Depends on: 26-153 (needs the phone).
  Gated on Q1.*

**Two-way link (GAP-C):**

- **26-156 [calendar] — store + expose the originating conversation id (C1).** Opaque
  `origin_conversation_id` on the booking (migration), persisted from the chat-supplied value, echoed as
  nullable `OriginConversationId` on `ConfirmedBookingResponse`; **ADR** amending `adr/0065` guard 2.
  Green = a chat-created booking's payload carries its conversation id; others carry null. *Migration
  lane. Depends on: none (but naturally sequences after 26-150, same flow).*
- **26-157 [android] — booking → dialog navigation (C1 client).** Carry `originConversationId` onto
  `ConfirmedBooking`; the detail sheet shows «Перейти к диалогу» when present → opens the thread. Green =
  tapping it opens the right conversation; absent when null. *Depends on: 26-156, 26-154.*
- **26-158 [chat] — record the resulting bookingId on the module task (C2).** Module confirmation wire
  carries `bookingId`; `ModuleTask.ResultBookingId` (migration) + `RecordResult`. Green = a completed
  in-dialog booking stores its `bookingId` on the task. *Migration lane. Depends on: none. Gated on Q7.*
- **26-159 [android] — dialog → booking navigation (C2 client).** The in-dialog booking chip shows
  «Открыть запись» when it carries a `bookingId` → opens Записи → Утверждены, selects the day, focuses
  the row (list gains a "focus this bookingId" nav arg). Green = tapping it lands on the highlighted
  booking. *Depends on: 26-158. Gated on Q7.*

*Ordering rationale:* the name-collection tickets (26-150/151) are the smallest change that fixes the
author's loudest complaint and can land first and independently. The phone tickets (26-153/154/155) are
Android-only and parallelisable. The link tickets split cleanly by direction — C1 (26-156/157) before C2
(26-158/159), so the most-asked jump ships first (Q7). Two migrations are needed
(`origin_conversation_id` on calendar, `result_booking_id` on chat) and take the single migration lane
one at a time (rule 13). Distinct files/repos keep the non-migration tickets non-interfering.

---

## Appendix — key source references (verified 2026-09-25)

| Fact | File |
|---|---|
| Confirmed payload carries name/phone/masked/customerId | `ago-calendar/src/Ago.Calendar.Contracts/ConsoleContracts.cs:202` |
| Read store projects `c.display_name`, `c.phone` | `ago-calendar/src/Ago.Calendar.Infrastructure.Postgres/ConfirmedBookingReadStore.cs:41-43` |
| Android row renders name, falls back to `shortId(customerId)` | `ago-android/app/.../bookings/ConfirmedBookingsScreen.kt:196-210` |
| `shortId` = hex prefix (`7c4e18f0`) | `ago-android/app/.../ui/components/IdentifierText.kt` |
| Chat flow books with `DisplayName: null`; no name step | `ago-calendar/src/.../ChatModuleTask/ReplyToModuleTaskHandler.cs:411`; `ChatBookingTaskState.cs` |
| `BookEvent.DisplayName` → customer upsert plumbing exists | `ago-calendar/src/.../BookEvent/BookEvent.cs:79`; `BookEventHandler.cs:230` |
| Public booking `DisplayName` optional | `ago-calendar/src/Ago.Calendar.Contracts/BookEventRequest.cs:27` |
| Carryover writes phone only, no name | `ago-calendar/src/.../ContactCollectedCustomerStore.cs` |
| Chat holds visitor name as contact-detail | `ago-chat/src/Ago.Chat.Domain/VisitorContactDetailKind.cs:26` (`25-62`) |
| Calendar reveal endpoint + Android client exist | `ConsoleContracts.cs:220`; `KtorBookingsApi.revealCustomerPhone` (`26-53`) |
| Calendar discards conversationId (guard 2) | `ago-calendar/src/Ago.Calendar.Domain/ChatBookingTask.cs:22-25` |
| Chat `ModuleTask` has ConversationId + ExternalTaskId, no result bookingId | `ago-chat/src/Ago.Chat.Domain/ModuleTask.cs:22,28` |
| Console shows null name as «не записано» | `ago-console/src/pages/CalendarBookingsPage.tsx:256` |
</content>
</invoke>
