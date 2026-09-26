# 26-112 · Записи list — real names + reachable contact, and a two-way dialog ⇄ booking link — design & scoping

- **Stage**: 26 (Android app)
- **Kind**: design/scoping pass. No production code. Deliverables: this spec, the refined mockup
  (`assets/26-112-bookings-refined-mockup.html`, unchanged by the refresh — it already draws the target:
  real name, phone behind a tap, master-grouped/day-selected shape), a proposed implementation-ticket
  breakdown (§7) + product questions (§6) for the author to approve.
- **Item**: `docs/backlog/26-112-design-bookings-show-names-contacts-and-dialog-booking-navigation.md`
- **Sibling in flight**: `docs/design/26-111-thread-contact-detail-panel.md` — the in-dialog
  contact-detail bottom sheet. §5 states the boundary between the two so the contact/phone reveal does
  not diverge.
- **Author's overriding principle**: the mockup is the agreed target — "make it convenient; we build
  it." Where the real API cannot deliver a mockup element, this doc proposes the concrete additive API
  change (repo / endpoint / DTO / field / migration), never a "skip it because the API lacks it."

> **Refresh, 2026-09-26.** The first version of this doc (2026-09-25) was written against the pre-`adr/0184`
> model, where the calendar owned a `customers` table with a `display_name` column. `adr/0184` (option B)
> has since shipped and is deployed: **chat owns the Person; the calendar dropped `customers` and keeps only
> a thin `person_records` table (phone, verification marks, no-show — no name) keyed by `person_id`; the
> name is read by the consoles from chat's `GET /api/v1/persons?ids=` and display-merged onto the booking
> rows** (`26-161` console, `26-162` Android). Every finding below is re-derived against that model. The
> structure, the mockup, and the principle above are kept; §0, §2, §6, §7 and the appendix are rewritten.

---

## 0. The headline finding (read this first)

**After `26-161`/`26-162`, a confirmed booking's row shows a name if and only if chat's Person has one.**
Chat's Person has a name if and only if a `VisitorContactDetail` of kind `Name` exists for that visitor
(`GetPersonsHandler.ToProfile`: the most recently recorded `Name` detail becomes `PersonProfileDto.DisplayName`;
"never invented from a phone number"). The calendar holds no name at all any more and cannot be the fix.

The author's live test (a confirmed booking on the stand shows only the masked phone) is therefore not a
display bug and not a lost-in-transit bug — both of those are gone with `adr/0184`. It is exactly **GAP-A:
the Person behind that booking has no `Name` detail, because no step of the chat booking flow ever writes
one.** Concretely, on `origin/main` today:

- The chat-driven booking (`ago-calendar` `ReplyToModuleTaskHandler.HandlePhoneProvidedAsync`) books with
  `DisplayName: null, PersonId: <chat visitor id>, OriginConversationId: <conversation id>`. For a chat-origin
  booking `BookEventHandler` does **not** publish `PersonRegistered` (only when `PersonId` is null — the
  dormant public/operator path), so even if the calendar were handed a name it would have nowhere legitimate
  to put it. The step machine is still service → worker → date → slot → phone → complete; **no name step.**
- The only writers of a `Name` detail are: (1) the widget's contact-capture form (`23-58`, name+phone+email
  all required), which `25-146` shows **at the module's phone-collection step**; (2) the `25-138` server-side
  gate, which asks phone then name **only for Telegram/MAX visitors**, before the first reply reaches the
  module; (3) `RegisterExternalPersonHandler`, from `PersonRegistered.Name`, for a no-chat-origin booking
  (dormant); (4) an operator typing it in the console.
- **The deterministic hole:** chat resolves `KnownPhone` from the Person's most recent `Phone` detail
  (`ResolveKnownPhoneAsync`) and, with the tenant's `AcceptUnverifiedPhone` on (`25-137`'s live setup), the
  calendar **skips the phone step entirely** (`HandleSlotChosenAsync` → `HandlePhoneProvidedAsync` directly).
  A widget visitor whose Person already has a phone but no name — an earlier conversation, an operator-entered
  phone, a name later deleted, a pre-`23-58` capture — therefore never sees the `25-146` form, is asked for a
  name by nobody, and books nameless. The same holds for any raw reply that bypasses the widget (a named,
  accepted limitation of a client-side gate, `25-136`/`25-138`). Nothing server-side guards the name for the
  widget channel at all.

**Where the name lives now, and where it must be collected:** the name lives in **chat's Person only**
(`visitor_contact_details`, kind `Name`). A booking references the Person by `person_id`; the consoles merge
the name in at display time. So the collection fix must be **chat-side, writing a `Name` detail through the
existing `RecordVisitorContactDetailHandler.HandleAsVisitorAsync` path** (consent-gated, rate-limited — the
one path `25-138` already uses). The calendar must **not** grow a name step: it would be collecting a fact it
no longer owns (`adr/0184` decisions 1 and 3) with no legitimate store for it. The one exception is the
no-chat-origin path, where the calendar already relays a typed `DisplayName` once via `PersonRegistered.Name`
and keeps nothing — correct as is.

**What is already done since the first version of this doc** (so no ticket rebuilds it):

| Gap in v1 | State now |
|---|---|
| GAP-B (phone from a booking) | **Shipped.** `26-117` built the row-tap detail sheet with the audited reveal (`surface = "AndroidBookings"`, `BookingRevealSurface.kt`); `26-125` fixed the fallback mask; `26-135` (cosmetics) is open. |
| A4 (never the hex `shortId`) | **Shipped.** `ConfirmedBookingIdentity`: name → masked phone → «Без имени». |
| GAP-C1 server (booking → dialog) | **Shipped.** `26-136` stores `events.origin_conversation_id` (indexed); `26-121` echoes it as `ConfirmedBookingResponse.OriginConversationId`. The `adr/0065` guard-2 amendment v1 asked for is recorded in `adr/0184` ("carries an opaque person id / origin id, interprets nothing"). |
| GAP-C1 Android client | **Shipped.** `26-117` wired «Перейти к диалогу» + the row's chat icon to `originConversationId`; live since `26-121`. |
| GAP-C1 web console | **Open.** `ago-console`'s `calendarApi.ts`/`CalendarBookingsPage.tsx` carry no `originConversationId` and offer no dialog link (verified by grep, `26-161` did not add it). |
| A3 (retro carryover of chat names into `customers.display_name`) | **Dissolved.** There is no `customers` table and no carryover; the Person *is* the source. |
| GAP-C2 (dialog → booking) | **Open**, and cheaper than v1 proposed — see §2. |

The «Сова · Клубника» emoji pair is chat's visitor handle, not a calendar field; the calendar row has no emoji
identity and the mockup does not draw one.

---

## 1. Element-by-element map (mockup slot → real data source today)

"Android client" = whether `ago-android` already has the field/adapter. **GAP-x** cross-references §2.

| # | Mockup slot | Backend source today | Android today | Status |
|---|---|---|---|---|
| R1 | Row start time (10:00) | `ConfirmedBookingResponse.StartsAt` | `ConfirmedBooking.startsAt` | **EXISTS** |
| R2 | Service title (Стрижка) | `ConfirmedBookingResponse.ServiceName` (nullable) | `ConfirmedBooking.serviceName` | **EXISTS** |
| R3 | **Client-name slot (red box)** | `ConfirmedBookingResponse.PersonId` → chat `GET /api/v1/persons?ids=` → `PersonProfileDto.DisplayName` (most recent `Name` detail, else null) | `KtorPersonsApi` + `ConfirmedBookingsViewModel` display-merge (`26-162`); null → `ConfirmedBookingIdentity` fallback | **PARTIAL — plumbing and render complete; the datum is empty whenever the chat flow never asked a name. GAP-A** |
| R4 | Duration («60 мин») | derived from `StartsAt`/`EndsAt` | derived on-device | **EXISTS** |
| R5 | Row → view contact / phone | `Phone` + `Masked` on every row; reveal `POST /api/v1/console/contacts/{personId}/reveal-phone` | detail sheet + `revealCustomerPhone` (`26-117`) | **EXISTS** (`26-135` cosmetics pending) |
| R6 | Row → jump to originating dialog | `ConfirmedBookingResponse.OriginConversationId` (`26-121`) | chat icon + «Перейти к диалогу» (`26-117`) | **EXISTS on Android; missing on the web console — GAP-C1w** |
| G1 | Master group header + count | server order `local_date, w.display_name, min(starts_at)`; grouped client-side | `groupByDayThenWorker` + `WorkerGroupHeader` | **EXISTS** |
| G2 | Day strip with per-day dots + month labels | `LocalDate`/`Weekday` per row | `ConfirmedDateStrip` (`26-117`) | **EXISTS** |
| G3 | Tabs «Ожидают (2) \| Утверждены \| Клиенты» | pending/confirmed/contacts reads | `BookingsTab` | **EXISTS** |
| D1 | In-dialog booking step → jump to Записи→Утверждены at this booking | the transcript's `confirmation_card` message carries `title` + `lines` only; **no `bookingId`** anywhere on the chat side | thread renders the plain-text body; no affordance | **GAP-C2** |

---

## 2. Gaps — and the concrete additive change that closes each (no "skip it")

### GAP-A — the client-name slot (R3): the Person has no name because the chat flow never asks for one

The datum has a store (chat's `Name` detail), a read API (`/api/v1/persons`), a display-merge on both consoles
and a rendered slot — **all present**. The only missing thing is a step that *asks for the name when the Person
lacks one*, on every channel, server-side. Precedent exists in full: `25-138`'s `ResolveContactGateAsync` /
`BuildContactGateStep` / `ContinueContactGateReplyAsync` already implement "check the Person's details, insert a
Chat-only `form` step for whatever is missing, record the answer through `RecordVisitorContactDetailHandler`,
then forward the visitor's original trigger to the module unchanged" — gated today on
`ChannelKind.Telegram or Max` **only**. The widget renders that step already: a `form` with `fieldId: "phone"`
is what `isPhoneCollectionStep` turns into the rich name+phone+email control (`25-146`), and `fieldId: "name"`
is the plain single-field form.

Three placements are possible; **which one is the author's call (Q-A)**. All are `ago-chat` only, none needs a
migration, a calendar change, or a wire-shape change:

- **A-1 — one uniform front gate.** Drop the `Telegram or Max` condition: every channel is asked, before the
  first reply reaches the module, for whatever of {phone, name} the Person lacks. Guarantees a named Person on
  every honest *and* raw-reply path. Cost: a first-time widget visitor meets the contact form before choosing a
  service — the "wall up front" the author explicitly moved away from in `25-146`. **Size S.**
- **A-2 — post-completion backstop.** When the module returns `Complete: true` and the Person has no `Name`,
  chat appends its own `form` step («Спасибо, запись создана. Как к вам обращаться?») as a Chat-only task,
  recorded through the same path. Never blocks the slot, never re-asks a known name, respects `25-146`'s
  placement, channel-neutral. Does not *guarantee* a name — a visitor who leaves stays nameless (the shipped
  masked-phone fallback covers the row). **Size S.**
- **A-3 (recommended) — front gate for the partially-known, late form for the unknown.** Generalise
  `ResolveContactGateAsync` to every channel with one extra rule for the widget channel: a Person with a phone
  on file but no name gets the single name question up front (this is precisely the hole in §0 — the phone
  step it would otherwise ride is skipped); a Person with nothing on file is left to `25-146`'s late form, which
  collects both. Telegram/MAX behaviour unchanged. No re-ask anywhere, no wall for newcomers, closes the
  deterministic hole. Raw replies from a fully-unknown widget visitor remain the named `25-136` limitation
  unless A-2 is added as the backstop. **Size S–M** (the gate's `Clear` rule gains one branch + tests for the
  five Done-when shapes `25-138` already uses).

*Teaching note:* in v1 the fix was "add `AwaitingName` to the calendar's `ChatBookingTask`". That is now the
wrong layer, not merely a different one: `adr/0184` made the display name a chat-owned attribute, and the
calendar has no store for it — a calendar name step would have to hand the value back to chat over a new event
for chat to record, which is the very copy the author rejected. Putting the ask in chat's router is the
dependency rule applied to data ownership: the owner of the fact asks for the fact. The alternative — a
`PersonNameProvided` event from the calendar — would work, but adds a message type to move a string one hop
when chat already sits in front of every reply.

**A-4 — the no-chat-origin path (public widget / operator-entered; dormant behind `PublicBookingApiGate`).**
`BookEventRequest.DisplayName` is still `string?` and unenforced; `BookEventHandler` relays it once via
`PersonRegistered.Name` and chat's `RegisterExternalPersonHandler` records it as a `Name` detail — the plumbing
is right. When that gate reopens, make `DisplayName` required in `BookEventHandler` (public optional → required
contract change; `api-design.md` line) and mandatory in the widget's public booking form. **Size S**, gated on
Q-D; not a stand-visible problem today.

A note, not a ticket: a phone typed at the module's own phone step reaches `person_records.phone` but never
chat's Person (chat records nothing from a module reply; only the `25-146` rich form and the `25-138` gate write
a `Phone` detail). On the live configuration the step is skipped whenever a phone is known, so the divergence
only arises on the verified-phone path or a raw reply. Recorded here so the next reader of `personal-data.md`
does not assume the two phone stores always agree.

### GAP-B — view the contact / phone from a booking (R5): shipped

`26-117` (sheet + reveal), `26-125` (mask fix). `26-135` (label sizes, alignment, dividers, one-row actions) is
the remaining cosmetic pass. Nothing to add here.

### GAP-C — the two-way dialog ⇄ booking link

#### C1 — booking → dialog: shipped on the backend and Android; missing on the web console

`events.origin_conversation_id` (`26-136`, indexed) → `ConfirmedBookingResponse.OriginConversationId` (`26-121`)
→ Android chat icon + «Перейти к диалогу» (`26-117`). **Open remainder (C1w):** `ago-console` — add
`originConversationId` to the `ConfirmedBooking` DTO in `calendarApi.ts` and a «Перейти к диалогу» affordance
on `CalendarBookingsPage.tsx` rows that carry it, navigating to `/conversations/{id}` (the route
`WorkspaceLayout` already owns). Absent when null. **Size S**, console only, no backend change.

#### C2 — dialog → booking: open, and now migration-free

v1 proposed a chat migration (`module_tasks.result_booking_id`) and a module-wire change. Neither is needed:

- The calendar's confirmation step is serialised as `ConfirmationCardPayload(title, lines)`
  (`ChatModuleTaskEndpoints.cs`); the payload is opaque JSON to chat (`adr/0065`), which reads only `title`/`lines`
  for its plain-text rendering (`PrimitiveTextRenderer`) and persists the whole element on the transcript
  message (`MessageContent.Payload`) and on `ModuleTask.LastStepPayload`.
- The operator-side `MessageDto` already carries `ContentKind`, `Content` (a `JsonElement`) and `Actions`
  (`14-06`, additive) — every operator client already receives the payload; none reads it yet (Android's
  `ThreadScreen` and the console thread render `Body` only).

**Proposed:**

- **C2-s [calendar]** — `ConfirmationCardPayload` gains `bookingId` (the `BookingConfirmation.BookingId`
  already in `HandlePhoneProvidedAsync`) and `localDate` (so a client can select the day without a lookup).
  Additive fields on the calendar's own payload; chat's renderer ignores unknown fields; no chat change, no
  migration. **Size S.**
- **C2-a [android]** — the thread renders a `confirmation_card` message whose `content.bookingId` is present
  with an «Открыть запись» affordance → Записи → Утверждены with a `focusBookingId` + `localDate` argument:
  select the day in the strip, scroll to and highlight the row; if the booking is no longer in the range (moved,
  cancelled) show a non-error "запись не найдена" state. **Size M.** Depends on C2-s.
- **C2-c [console]** — the same affordance in the console thread; lower priority. **Size S–M.**

*Teaching note:* reading `content.bookingId` on the client does **not** breach chat's opacity rule — that rule
binds `Ago.Chat.*` code (guarded by `MessageOpacityTests`), and chat's code stays byte-for-byte unaware. The
Android app and the console are `adr/0093`'s "one console, each screen talks to the owning product"; they
already speak both products' contracts, and `ConfirmationCardPayload` is a published `Ago.Calendar.Contracts`
type. The alternative — a calendar read `GET /console/confirmed-bookings?originConversationId=` — is also
migration-free (the index exists) but costs a round trip, cannot distinguish two bookings made in one
conversation, and teaches the calendar a query it has no other use for. Payload first; the lookup remains
available if the author prefers the transcript to carry no product ids at all (Q-B).

---

## 3. How the name is displayed in the row (the red-boxed slot)

Shipped in `26-117`/`26-125` and unchanged by the refresh:

- **Primary line = the real name**, bold — `ConfirmedBookingIdentity.Name` from the display-merged
  `PersonProfileDto.DisplayName`; the start time on the right.
- **Fallback:** masked phone (`MaskedPhone`, client-masked when the wire flag is false — `26-125` bug 4) →
  «Без имени» (`NoName`). **The hex `shortId` is never the identity again.** The console renders the same null
  as «не записано», and a chat-API outage as "name not shown yet" (`usePersonNames` — degrade, never blank,
  `adr/0184`'s named consequence).
- **Second line = service · duration**; two trailing icons always present, chat then phone (`26-117` hard
  requirement 5).

The emoji-pair handle is not drawn.

---

## 4. The two-way navigation design (summary)

- **Confirmed booking → dialog** (C1): row chat icon, or detail sheet → «Перейти к диалогу» (enabled when
  `originConversationId` is present, disabled when null — `26-117` chose *disabled, always present* over
  *absent*; Q-E asks whether that stands) → opens the thread. **Android shipped; console open (C1w).**
- **In-dialog booking step → booking** (C2): the transcript's confirmation card, once its payload carries a
  `bookingId`, shows «Открыть запись» → Записи → Утверждены, day selected, row focused.
- **The empty case** (widget/operator booking with no conversation) is real and expected; the affordance is
  disabled, not an error.

---

## 5. Boundary with 26-111 (contact/phone reveal must stay coherent)

Unchanged in substance; the key names moved with `adr/0184`:

- **Same UX + same result vocabulary.** «Показать», `RevealPhoneResult` (`Revealed/Refused/Failed`), server
  sends the unmasked value, masked-stays-on-failure.
- **Different endpoints, on purpose.** A conversation's contact detail is chat data —
  `POST /api/v1/conversations/{id}/contact-details/{id}/reveal` (`conversation:read`). A booking's phone is the
  calendar's rule-8 operational fact — `POST /api/v1/console/contacts/{personId}/reveal-phone` (`customer:read`),
  keyed by the booking's `personId`. Separate audit trails on each side; collapsing them would cross the
  product line. The *name* shown on both sheets is one fact from one place (chat's Person), which is exactly
  what `adr/0184` bought.
- **`surface` distinguishes them in the audit:** `AndroidThread` vs `AndroidBookings`
  (`BookingRevealSurface.ANDROID_BOOKINGS`, already in use).

---

## 6. Product questions (not decided here — CLAUDE.md rule 14 "file as the question")

Consolidated from v1's Q1–Q8. Dropped because the new model or shipped work already answers them: Q1 fallback
(shipped: masked phone → «Без имени»), Q2 phone placement (shipped: behind the sheet), Q6 retro carryover
(dissolved with `customers`), Q8 grouping (shipped, keeps the author's shape). Q3/Q5 fold into Q-A/Q-D, Q4 into
Q-E, Q7 into Q-B.

**Q-A — Where does chat ask the name?** (the only decision GAP-A needs)
- *A-1* uniform front gate on every channel — simplest rule, guarantees a name even against raw replies, but
  reinstates the up-front form `25-146` removed for first-time widget visitors.
- *A-2* post-booking ask when the Person is still nameless — never blocks, never re-asks, no guarantee.
- *A-3* front gate only for a *partially known* Person (phone, no name — the live hole), late `25-146` form for
  the unknown; Telegram/MAX unchanged. **Recommended**, optionally with A-2 as the backstop.

**Q-B — C2 mechanism and timing.** `bookingId`+`localDate` in the confirmation-card payload (recommended;
exact booking, no round trip, migration-free) vs a calendar lookup by `originConversationId` (also
migration-free, one hop, ambiguous for repeat bookings). Ship Android C2 now, or as a fast-follow after
GAP-A/C1w? Recommendation: GAP-A first, then C1w + C2 together (they share the "link" story).

**Q-C — Web-console parity.** C1w (dialog link on the bookings page) is S and closes the console gap now; the
console thread's «Открыть запись» (C2-c) can wait for the Android version to prove the interaction.
Recommendation: C1w now, C2-c later.

**Q-D — The dormant public/operator booking path.** Make `DisplayName` required (calendar validation + widget
public form) when `PublicBookingApiGate` reopens, or decide now? Recommendation: fold it into whichever ticket
reopens the gate; the `PersonRegistered.Name` plumbing already carries it.

**Q-E — A booking with no linked dialog.** `26-117` shipped the chat icon *always present, disabled* when
`originConversationId` is null (hard requirement 5); v1 recommended *absent*. Keep as shipped?
Recommendation: keep — it was the author's own requirement and keeps every row the same width.

---

## 7. Proposed implementation-ticket breakdown

Each is one promise that lands green (rule 15). **Not filed here; numbers are provisional placeholders
(P1…P7) — the managing session assigns real ones (next free ≈ `26-163`).** Repo tags: **[chat]**,
**[calendar]**, **[console]**, **[android]**, **[widget]**. **No ticket below needs a migration**, so none
takes the migration lane.

**Data collection — the name (GAP-A):**

- **P1 [chat] — a chat booking's Person gets a name: the contact gate asks for what the Person lacks (A-3).**
  `RouteConversationToModuleHandler.ResolveContactGateAsync` applies to every channel; for the widget channel it
  returns `NeedsName` when a `Phone` detail exists and no `Name` does, and `Clear` when nothing is on file (the
  `25-146` form collects both later). Telegram/MAX behaviour identical to today. Green = a widget visitor with
  a phone on file and no name who triggers a booking is asked for a name before the module starts, the answer
  is a `Name` detail, and `GET /api/v1/persons?ids=` returns it (handler tests in the `25-138` style, one per
  branch). *Shape depends on Q-A (A-1 is the same ticket with the widget branch removed). No migration. Depends
  on: none.*
- **P2 [chat] — post-booking name backstop (A-2).** On `Complete: true` with a nameless Person, chat appends its
  own `form` name step as a Chat-only task and records the answer. Green = a completed nameless booking is
  followed by the name ask; the answer lands on the Person. *Optional — gated on Q-A. Depends on: none
  (naturally after P1).*

**Two-way link (GAP-C):**

- **P3 [console] — bookings page links to the originating dialog (C1w).** `originConversationId` on the
  `ConfirmedBooking` DTO; «Перейти к диалогу» on rows that carry it → `/conversations/{id}`; absent when null;
  page test + ux-gate fixture. Green = a chat-origin booking's row opens the right conversation. *Depends on:
  none.*
- **P4 [calendar] — the confirmation card carries the booking it made (C2-s).** `ConfirmationCardPayload` gains
  `bookingId` + `localDate`, threaded from `BookingConfirmation` through `ModuleStep.ConfirmationStep`. Green =
  the payload carries both; `ago-chat`'s `PrimitiveTextRenderer` output is unchanged (contract test on both
  sides). *No migration. Depends on: none.*
- **P5 [android] — «Открыть запись» from the in-dialog confirmation card (C2-a).** Thread reads
  `content.bookingId`/`localDate` off a `confirmation_card` message; Записи → Утверждены accepts a focus
  argument, selects the day, scrolls to and highlights the row; "не найдена" state when out of range. Strings as
  resources, both languages. Green = tapping the card lands on the highlighted booking. *Depends on: P4.*
- **P6 [console] — «Открыть запись» in the console thread (C2-c).** Same affordance → `/calendar/bookings`
  with the day and row focused. *Depends on: P4. Lower priority (Q-C).*

**The dormant path:**

- **P7 [calendar + widget] — the public booking requires a name (A-4).** `BookEventHandler` refuses a blank
  `DisplayName`; the widget's public booking form makes it mandatory; `api-design.md` line. Green = a public
  booking without a name is refused; with one, chat's Person is created with it via `PersonRegistered`.
  *Gated on Q-D and on `PublicBookingApiGate` reopening. Depends on: none.*

**Tickets from v1 that are now unnecessary, and why:**

| v1 placeholder | Fate |
|---|---|
| 26-150 [calendar] name step in `ChatBookingTask` | **Replaced by P1** — the calendar no longer owns a name (`adr/0184`); collecting it there would need a new event to hand it back to chat. |
| 26-151 [calendar + widget] public name required | **→ P7**, deferred behind the public gate. |
| 26-152 [calendar] carry chat names into `customers.display_name` | **Dissolved** — no `customers`, no carryover; the Person is read directly. |
| 26-153 / 26-154 / 26-155 [android] phone fields, detail sheet, name fallback | **Shipped** as `26-117` + `26-125`; `26-135` carries the cosmetics. |
| 26-156 [calendar] `origin_conversation_id` + ADR amending `adr/0065` guard 2 | **Shipped** as `26-136` + `26-121`; the guard-2 reasoning lives in `adr/0184`. |
| 26-157 [android] booking → dialog navigation | **Shipped** in `26-117`, live since `26-121`. |
| 26-158 [chat] `ModuleTask.ResultBookingId` + migration + module-wire field | **Unnecessary** — the payload already reaches the transcript and the operator DTO; P4 adds the field where the calendar owns it. |
| 26-159 [android] dialog → booking navigation | **→ P5**, without the chat dependency. |

*Ordering rationale:* P1 is the smallest change that fixes the author's loudest complaint and is independent
of everything else. P3 and P4 are independent S-size tickets in different repos and can run in parallel with
P1 (files do not overlap: chat router vs console page vs calendar contracts/endpoint). P5 waits for P4; P6 for
P4 and the author's Q-C answer. P2 and P7 are gated on Q-A/Q-D. The whole set needs **zero migrations**, which
is the practical dividend of `adr/0184` having put the name where it is read from.

---

## Appendix — key source references (re-verified 2026-09-26 against `origin/main`)

| Fact | File |
|---|---|
| Confirmed payload: `PersonId`, `Phone`, `Masked`, `OriginConversationId`; no name | `ago-calendar/src/Ago.Calendar.Contracts/ConsoleContracts.cs:280-294` |
| Read store joins `person_records` for the phone; no name column | `ago-calendar/src/Ago.Calendar.Infrastructure.Postgres/ConfirmedBookingReadStore.cs` (`Sql`) |
| `customers` dropped; `person_records` created (phone, marks, no-show) | `ago-calendar/.../Migrations/20260925212825_Stage26PersonRecordsReplaceCustomers.cs` |
| `events.origin_conversation_id` + `person_id`, both indexed | `ago-calendar/.../Migrations/20260925124249_Stage26AddEventPersonAndOriginConversation.cs` |
| Chat flow books `DisplayName: null`, `PersonId`, `OriginConversationId`; no name step | `ago-calendar/src/.../ChatModuleTask/ReplyToModuleTaskHandler.cs:422-425`; `ChatBookingTaskState.cs` |
| Phone step skipped when `KnownPhone` + `AcceptUnverifiedPhone` | `ReplyToModuleTaskHandler.cs:381-386` (`HandleSlotChosenAsync`) |
| `PersonRegistered{Name}` published only for a no-chat-origin booking | `ago-calendar/src/.../BookEvent/BookEventHandler.cs:237-240`; `Contracts/PersonRegistered.cs` |
| Confirmation payload = `title` + `lines` only | `ago-calendar/src/Ago.Calendar.Api/ChatModule/ChatModuleTaskEndpoints.cs:180-184`; `BookingConfirmation.BookingId` in `Ago.Calendar.Application/Abstractions/IBookingStore.cs:180` |
| Public booking endpoint behind `PublicBookingApiGate` | `ago-calendar/src/Ago.Calendar.Api/Booking/BookingEndpoints.cs:20-25` |
| Person name = most recent `Name` detail; never from a phone | `ago-chat/src/Ago.Chat.Application/UseCases/GetPersons/GetPersonsHandler.cs:82-88`; `PersonProfileDto.cs` |
| Person read API, operator-only, batch `?ids=` | `ago-chat/src/Ago.Chat.Api/Persons/PersonEndpoints.cs:27-31` |
| `25-138` gate: Telegram/MAX only, phone then name, records via the standard path | `ago-chat/src/.../RouteConversationToModule/RouteConversationToModuleHandler.cs:388-395, 519-534, 614-680` |
| `KnownPhone` = most recent `Phone` detail | `RouteConversationToModuleHandler.cs:1161-1169` |
| `PersonRegistered` → Person + `Name`/`Phone` details, idempotent | `ago-chat/src/.../RegisterExternalPerson/RegisterExternalPersonHandler.cs` |
| Operator `MessageDto` carries `ContentKind`/`Content`/`Actions` | `ago-chat/src/Ago.Chat.Contracts/MessageDto.cs:3-7` |
| Step persisted on the transcript with its content | `RouteConversationToModuleHandler.cs` `FinishStepAsync` (`MessageContent.Create` → `AddSystemMessage(..., content)`) |
| Widget contact form (name+phone+email required) shown at the phone step; client-side only | `ago-widget/src/ui/widget.ts:3163-3185`; `src/ui/contactCapture.ts` |
| Console display-merge, degrade-never-blank | `ago-console/src/calendar/usePersonNames.ts`; `src/api/personsApi.ts`; `CalendarBookingsPage.tsx:140,262` |
| Console bookings page has no `originConversationId` / dialog link | `ago-console/src/api/calendarApi.ts`, `src/pages/CalendarBookingsPage.tsx` (grep: none) |
| Android identity fallback name → masked phone → «Без имени» | `ago-android/core/domain/.../bookings/ConfirmedBookingIdentity.kt` |
| Android display-merge + dialog link wired | `ago-android/core/domain/.../bookings/ConfirmedBooking.kt`; `app/.../bookings/ConfirmedBookingsScreen.kt:146-150, 521` |
| Android reveal surface label | `ago-android/core/domain/.../bookings/BookingRevealSurface.kt` (`AndroidBookings`) |
