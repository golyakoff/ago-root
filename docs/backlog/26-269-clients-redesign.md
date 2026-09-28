# 26-269 · [design] Записи ▸ Клиенты redesign — a phone operator's working surface (mirror: console + android)

- **Stage**: 26. Kind: research + design proposal + recommended ticket breakdown (this file is the design;
  the slices in §8 are filed as their own numbered items). Author need stated 2026-09-28.
- **Status**: proposed — not yet sliced into GitHub issues. This document is the research deliverable for
  the managing session to slice from.
- **Repos touched by the feature**: `ago-calendar` (one new per-person bookings read), `ago-chat` (one new
  per-person conversations read), `ago-console` + `ago-android` (the two operator surfaces). No platform
  change. Mockup: `ago-android-design/clients.html`.

## The need (author, verbatim intent)

Записи ▸ Клиенты today is a **flat list of every client — no search, no filters, no way to open a client**
— just name, phone, and two ugly status sentences («Не подтверждён кодом» / «Не подтверждён оператором»).
It must become a genuinely useful working surface for an operator taking phone calls: search, a way to open
a client, that client's past and upcoming bookings, and a jump to their dialog. And the phone-status labels
must be replaced by the design site's existing warning-glyph pattern
(`<svg class="i" style="color:var(--warning)"><use href="#i-excl"/></svg>`, see `modules-faq.html`).

**UX constraints (honored, not re-litigated):**
- Reuse the **warning glyph** for phone status; no big scary sentences.
- Search by name / phone.
- A **past / future** split for a client's bookings.
- A **client-detail** view — the hub the two navigations (to a booking, to a dialog) launch from.

---

## 1. What exists today (cited), and what a working surface would add

### 1.1 The current Клиенты list

**Android** — `ago-android/app/src/main/kotlin/ago/chat/android/bookings/ContactsScreen.kt`
(`ContactsBody` / `ContactsList` / `ContactCard`), state in `ContactsUiState.kt`, VM in
`ContactsViewModel.kt`, gated as the third Записи sub-screen in `bookings/BookingsTab.kt`. It is a flat
`LazyColumn` of cards; its own doc comment states the design intent verbatim: *"a row that opens nothing is
fine, the list itself is the answer"* (`26-52`). Each card renders name (or the emoji identity /
masked phone when nameless), the phone with a `Показать` reveal (`26-53`), **two full-sentence status
lines** — `bookings_contacts_phone_verified_yes/no` and `bookings_contacts_phone_confirmed_yes/no` — and a
no-show count. No search, no filter, no tap target.

**Console** — `ago-console/src/pages/CalendarContactsPage.tsx` (`/calendar/contacts`). A `Table` with
columns phone (+`renderPhone` reveal), name (display-merged), no-shows, and **two badge columns**
`phoneVerified` (`tone="success"`) / `phoneConfirmed` (`tone="accent"`) with
`calendarContactsNotVerifiedLabel` / `calendarContactsNotConfirmedLabel` for the null state, plus
first-seen / last-seen. No search, no per-client drill-in, no booking or dialog navigation.

### 1.2 The read behind it (one read, one shape, both clients)

`GET /contacts` on the calendar → `Contact[]` (`ago-console/src/api/calendarApi.ts:420` `interface Contact`;
android `core/domain/.../bookings/Contact.kt`). Fields: `personId`, `phone`, `masked`, `noShowCount`,
`phoneVerifiedAt`, `phoneConfirmedByOperatorAt`, `firstSeenAt`, `lastSeenAt`. **Gated server-side on
`customer:read`.** The person's **name is not on this response** — it is read separately from chat's Person
registry by `personId` and **display-merged client-side**: console `usePersonNames` →
`GET /api/v1/persons?ids=` (`ago-console/src/api/personsApi.ts`, `calendar/usePersonNames.ts`); android
`ContactsViewModel.mergePersonDetails` → `PersonsApi` (`26-203`), which also supplies the stored emoji pair.
This is exactly the display-merge `adr/0184` decision 4 prescribes.

### 1.3 The person model split (adr/0184) — where each fact lives

`adr/0184` deleted the calendar's `customers` copy. Two stores, one identity:

- **Calendar `PersonRecord`** (`ago-calendar/src/Ago.Calendar.Domain/PersonRecord.cs`): keyed by the opaque
  `PersonId`, holds only the booking-domain / write-gating facts rule 8 forces the calendar to own —
  `Phone`, `NoShowCount`, `FirstSeenAt`, `LastSeenAt`, `PhoneVerifiedAt` (SMS-code proof, `20-09`),
  `PhoneConfirmedByOperatorAt` ("I called and it is them", `23-12`). **No name, no notes, no channel list.**
- **Chat `Visitor`/Person**: owns the display name, contact channels, the emoji pair, operator notes, and
  the person's **conversations**.

A client-detail that shows name + phone-status + bookings + dialog therefore **spans both products**, and by
`adr/0184` decision 4 it spans them **by client-side display-merge, never a server-to-server read**: the
console/android read the person (name, channels) from chat and the bookings from the calendar and merge.

### 1.4 The navigation targets to reuse (both already exist)

- **To a confirmed booking → reschedule.** Console: `CalendarBookingsPage.tsx` (`/calendar/bookings`) +
  `RescheduleBookingButton.tsx`; android: `bookings/ConfirmedBookingsScreen.kt` (its reschedule sheet +
  `onReschedule`, and `onOpenDialog`). The reschedule write is `26-208`/`adr/0187` — already merged. The
  booking rows come from `getConfirmedBookings(from, to)` → `ConfirmedBooking` (carries `originConversationId`,
  `personId`, times, service, worker, masked phone), `calendarApi.ts:695`.
- **To a dialog (active, else last read-only).** Console opens `<Link to={`/conversations/${id}`}>` from a
  booking's `originConversationId` (`CalendarBookingsPage.tsx:331`); android `onOpenDialog(conversationId)`
  → `ThreadScreen.kt`. A **closed** conversation opens as a read-only archive — the thread with no composer
  (dialogs.html draws this state at reduced opacity; the app's closed-dialog rule is "hide the composer, not
  grey it").

### 1.5 The data gap — what a working surface needs that no read gives today

1. **A client's bookings, past + upcoming, all held statuses.** Today the only bookings read is the
   **tenant-wide** `GET /confirmed-bookings?from&to` (a date window over *everyone*). There is **no
   "bookings for one person" read**. This is the one genuinely new **calendar** read the redesign needs.
2. **A client's conversations, active + past, by `personId`.** The existing visitor-history read is
   **conversation-scoped** — `GET /api/v1/conversations/{conversationId}/visitor-history`
   (`ago-chat/.../Conversations/ConversationsEndpoints.cs:227`): it answers "what else has *this
   visitor-in-this-conversation* done", starting from a conversation you already hold. From the Клиенты list
   we hold a `personId`, not a `conversationId`. Navigating a client → their dialog therefore needs a **new
   chat read keyed by person**: "the active conversation for this person, else the most recent one." This is
   the one genuinely new **chat** read.
3. **Search.** `/contacts` returns the whole flat list and the name lives in chat (already batch-fetched for
   the merge). For the tenant sizes this product targets (and zero real tenants today), **client-side
   filtering** of the loaded+merged list — by name and by phone — is the honest v1: no backend change, works
   the instant the list is on screen. A server-side search endpoint is a **scale follow-up**, not now
   (filed as a note in §8, not a v1 slice).

---

## 2. The operator cases — the author's three, plus the ones a phone shift actually needs

The author gave three and said they are likely missing some. The full set, each with where it resolves:

| # | Case (operator, on a call) | Resolves via |
|---|---|---|
| 1 | **Reschedule by phone.** Has name + phone, not the date; must reach that client's confirmed booking to move it. | Search → client detail → **Предстоящие** → tap booking → existing booking detail → reschedule (`26-208`). |
| 2 | **"Remind me what time we agreed."** | Same path as #1, read-only — the upcoming booking's time is on the detail. |
| 3 | **"Remind me what we discussed in chat."** | Search → client detail → **Открыть диалог**: the active conversation if one exists, else the **most recent, opened read-only**. |
| 4 | **See a client's whole history at a glance** — past + upcoming together. | The client detail *is* this: two segments, Предстоящие / Прошедшие. Underpins 1–3. |
| 5 | **Reliability check before committing a slot** — "they no-showed 3× — take prepayment / be careful." | `PersonRecord.NoShowCount` (already owned) shown as a pill on the row and detail. |
| 6 | **Quick-call / quick-message back.** | Detail actions: **Позвонить** (reveal-then-`tel:`, the reveal is audited, `26-53`) and **Открыть диалог** (case 3). |
| 7 | **Create a manual booking for this client.** | Detail action **Записать** → deep-links the `26-268` manual-booking flow with this person already recognized (skips phone-lookup + name). Depends on `26-268` landing. |
| 8 | **Confirm the phone by operator** — "I called, it's them." | The warning glyph is *actionable*: from the detail, **Подтвердить телефон** calls the **existing** `ConfirmOperatorVerifiedPhone` endpoint (sets `PhoneConfirmedByOperatorAt`, gated `customer:read`). No new backend. |
| 9 | **See a client's contact channels** (phone, email, …). | Display-merged from chat's Person (channels live there, `adr/0184`). Detail meta block. |

**Weighed and deliberately kept off the everyday phone-operator hub (with reasons):**

- **Operator notes about the person** — chat-owned (`adr/0184`); *editing* is gated `customer:edit` and
  already has a home in the dialog's contact panel (`NotesSection.kt`). Show a read-only note preview on the
  detail if cheap; do not build note editing here. (Not a v1 slice.)
- **Block / restrict** — visitor-restrictions (`block-visitor` / `lift`) are an **abuse** tool scoped to the
  chat visitor, not phone-client management; they belong on the restrictions surface
  (`visitor-restrictions.html`). At most a link from the detail; not built here.
- **GDPR erase** — a rare, destructive, permissioned admin act that (per `adr/0184`) deletes the chat Person
  and cascades the calendar record + events. It belongs on a dedicated personal-data / admin surface, not the
  hub an operator taps fifty times a shift. Not here.
- **Merge duplicates** — `adr/0184` moved merge to chat's Person registry and `adr/0147` forbids auto-merge
  (a phone is a hint, not proof). If ever wanted, it is a chat-side act; the detail may *surface* a
  same-phone hint but never merges. Not a v1 slice.

---

## 3. The redesigned list

Same Записи shell, the **Клиенты** segment (third of Ожидают / Утверждены / Клиенты — the seg is capped at
three, `booking.html` establishes this). Changes:

1. **A search field** at the top (`#i-search`), filtering the loaded+merged list by **name or phone** as the
   operator types. Client-side (§1.5.3). Empty-result is a stated empty state, not a blank area (the "empty
   is a state" rule `ContactsScreen`/`BookingsScreen` already apply).
2. **A tappable row that opens the client detail** — the single biggest change from `26-52`'s deliberately
   inert list. Row = avatar (emoji pair when chat has one, else initials, else `#i-user-plus` for a
   name-less manual client) + name (or the emoji identity / masked phone, **never a raw GUID** —
   `IdentifierText`'s rule) + a compact secondary line (masked phone · «N записей» / last-visit hint).
3. **Phone status as the warning glyph, not sentences.** Show
   `<svg class="i" style="color:var(--warning)"><use href="#i-excl"/></svg>` on the row **only when the phone
   is neither SMS-verified nor operator-confirmed** — the single actionable state. When it is verified
   *either* way, show **no icon** (confirmed is the quiet default; a green tick on every row is noise). A tap
   / long-press reveals the hint «Телефон не подтверждён»; the resolution lives on the detail (case 8). The
   two underlying facts (`PhoneVerifiedAt`, `PhoneConfirmedByOperatorAt`) stay two facts on the wire and on
   the detail — the glyph collapses only the *list-row* presentation of "actionable / not", never the facts.
4. **A no-show pill** when `noShowCount > 0` (case 5) — otherwise nothing (zero is the quiet default).
5. **The past/future question, answered where it belongs.** Past-vs-future is a property of a *booking*, not
   of a *client*, so the split lives **inside the client detail** (§4) as two segments. On the *list*, the
   useful expression is a lightweight filter chip — **С предстоящей записью** — that narrows to clients an
   operator is most likely calling about (cases 1–2), leaving «Все» as default. This resolves the author's
   uncertainty: the clean treatment is *a filter on the list, a split in the detail*, not a global toggle.

---

## 4. The client-detail view (the new hub)

A screen the list opens. Sections:

- **Header** — avatar + name (or emoji identity); masked phone with **Показать** (audited, `26-53`) then
  **Позвонить** (`tel:`); the warning glyph + **Подтвердить телефон** action when neither verified nor
  operator-confirmed (case 8, reuses `ConfirmOperatorVerifiedPhone`); a no-show pill when any (case 5).
- **Actions** — **Открыть диалог** (active else last read-only, case 3), **Записать** (deep-link `26-268`,
  case 7). **Открыть диалог** is hidden, not greyed, when the person has no conversation at all (a manual
  client per `26-268` has none) — the same "hide, don't grey" rule the confirmed-bookings screen uses for a
  null `originConversationId`.
- **Bookings** — two segments **Предстоящие / Прошедшие**, each a time-led list of *this client's* bookings
  (the new read, §1.5.1). Tapping a booking opens the existing booking detail, from which reschedule is
  reachable (cases 1–2). Predстоящие leads because that is what a phone call is usually about.
- **Meta** — contact channels (chat-owned display), first-seen / last-seen (calendar). Read-only.

The detail is a **pure read + navigation hub**: it composes existing writes (reschedule, operator-confirm,
manual booking), it introduces none of its own.

---

## 5. Read / data shape — respecting the adr/0184 split and Clean Architecture

| The surface needs | Source | Reuse or new |
|---|---|---|
| Client list (phone, no-show, verification facts) | calendar `GET /contacts` → `Contact[]` | **reuse** |
| Each client's name / emoji / channels | chat `GET /api/v1/persons?ids=` (+ person read for channels) | **reuse** (display-merge, `adr/0184` d.4) |
| Search by name/phone | client-side filter of the merged list | **new (client-side only, no backend)** |
| A client's bookings, past + upcoming | calendar — **no per-person read exists** | **NEW calendar read** (§1.5.1) |
| A client's active-or-last conversation | chat — visitor-history is conversation-scoped, not person-scoped | **NEW chat read** (§1.5.2) |
| Reschedule a booking | calendar `26-208`/`adr/0187` | **reuse** |
| Confirm phone by operator | calendar `ConfirmOperatorVerifiedPhone` (`23-12`) | **reuse** |
| Create a manual booking | calendar `26-268` flow (deep-link) | **reuse (once `26-268` lands)** |

**Clean-Architecture placement of the two new reads** (teaching note): each is a **query** in its owning
product's Application layer behind a read port, with the SQL/Dapper adapter in Infrastructure — the same
CQRS read split the project already uses (`adr/0004`: EF for writes, Dapper for read models). The dependency
rule keeps the query in Application (it names no `NpgsqlConnection`); the calendar's per-person bookings read
is a sibling of `GetConfirmedBookingsForTenantHandler`, filtered by `personId` instead of a tenant-wide
window. Neither read is on a write path, so **rule 8 does not apply** — they are display reads, and the
person→conversations read degrades to "no dialog to open yet" exactly as `adr/0184` decision 4 permits the
name-merge to degrade to "name not shown yet". Crucially, **both stay within products' own boundaries**: the
console/android call the calendar read and the chat read and merge on the client, so **no server-to-server
person read is introduced** — the invariant `adr/0184` decision 4 exists to protect.

---

## 6. ADR need — no new ADR; decisions recorded here

Unlike `26-268` (which needed `ADR-0188` for a new permission and a new *write* semantics), this redesign is
**reads + navigation + UI**. Every write it touches already exists and already has its ADR (reschedule
`adr/0187`, operator-confirm `23-12`, manual booking `26-268`/`ADR-0188`). The two new reads follow patterns
already decided:

- the per-person bookings read is `adr/0184` decision 4's display-merge, filtered — no new decision;
- the person→conversations read is a new read *shape* but introduces no new gate if it reuses
  `conversation:read` (the operator's own-queue permission) with the site scope the existing conversation
  reads use.

So: **no ADR.** The two design decisions worth pinning are recorded in this file: (a) **search is
client-side in v1** (server search is a scale follow-up), and (b) **past/future is a filter on the list and
a split in the detail**, because past-vs-future is a booking property, not a client property. If, when
building the person→conversations read, it turns out to need a *new* permission or a cross-product coupling,
that reopens the ADR question — flag it in the slice, do not decide it silently (Teaching-mode rule).

---

## 7. The mockup

`ago-android-design/clients.html` (this design pass): the redesigned list (search + the
С-предстоящей-записью filter + the warning-glyph phone status), the client-detail hub, and the three flows —
find→booking (cases 1–2), find→dialog **active**, find→dialog **read-only** (case 3) — plus the empty search
state and the actionable warning-glyph → Подтвердить телефон (case 8). Built entirely from the site's
existing classes and `tokens.js` glyphs (`#i-search`, `#i-excl`, `#i-call`, `#i-chat`, `#i-cal`,
`#i-check-circle`, `#i-user-plus`, `#i-back`, `#i-close`, `#i-plus`, `#i-more`); no invented glyph or color.
Wired like `manual-booking.html` — its own page, a nav link + TOC card in `index.html`, and a
`COPY clients.html …` line in the `Dockerfile` (the file lists every page by name; omitting the line 404s the
deployed page — this exact miss happened with `manual-booking.html`, `#19`).

---

## 8. Recommended ticket breakdown (one ticket = one promise that lands green — rule 15)

Filed as their own numbered items; mirror console + android per the "full console parity" standard.

1. **[ago-calendar] Per-person bookings read.** New Application query + Dapper read adapter + endpoint
   `GET /api/v1/console/contacts/{personId}/bookings` returning this person's bookings across held statuses
   (`PendingConfirmation` / `Booked` / `NoShow`), each row carrying enough to render and to open the existing
   booking detail (times, service, worker, status, `originConversationId`). Gated `customer:read`. One
   promise: an operator GETs one person's full booking history. **No migration** (query only). Not the
   migration lane.
2. **[ago-chat] Per-person conversations read.** New Application query + read adapter + endpoint
   `GET /api/v1/persons/{personId}/conversations` (or equivalent) returning the person's conversations with
   enough to pick **active, else most-recent** and open it (id + status + last-activity). Gated
   `conversation:read` with the existing conversation-read site scope. One promise: given a person, the
   client can resolve the one conversation to navigate to. **No migration.**
3. **[ago-console] Redesigned Клиенты list.** On `CalendarContactsPage.tsx`: a search field (client-side
   filter by name/phone over the merged list), replace the two verification badge columns with the
   **warning-glyph** treatment (glyph only when neither verified nor operator-confirmed), a no-show pill, and
   make each row open the client detail (route added in #4). `i18n` both languages, page test + fixture,
   `typecheck && lint && test && ux-gate` green. One promise: the console clients list is searchable and
   shows the compact glyph status. Depends on nothing new (uses existing `/contacts`).
4. **[ago-console] Client-detail page.** New route + page: header (reveal/call, warning-glyph →
   **Подтвердить телефон** via existing `ConfirmOperatorVerifiedPhone`), Предстоящие/Прошедшие bookings
   (consumes #1), **Открыть диалог** active-else-last-read-only (consumes #2), **Записать** deep-link to the
   `26-268` manual flow. i18n + tests + ux-gate. One promise: opening a client shows their bookings and the
   two navigations work. Depends on #1, #2.
5. **[ago-android] Redesigned Клиенты list.** On `ContactsScreen.kt`: search field, replace the two
   full-sentence status lines with the warning-glyph treatment, no-show pill, tappable rows → detail (screen
   in #6). All new strings as resources both languages (`feedback_android_strings_must_be_resources`); VM +
   tests. One promise. Uses existing `/contacts`.
6. **[ago-android] Client-detail screen.** New screen mirroring #4: header + reveal/call + warning-glyph →
   Подтвердить телефон, Предстоящие/Прошедшие (consumes #1), Открыть диалог active-else-read-only (consumes
   #2), Записать deep-link (`26-268`). String resources both languages; VM + tests. One promise. Depends on
   #1, #2.

**Order:** #1 and #2 (backend reads) first; #3 and #5 (list redesign) can start immediately in parallel (no
new backend); #4 and #6 (detail) follow once #1+#2 land. #7 (below) after `26-268` ships.

**Deferred / notes (not v1 slices):**
- **Server-side client search** — file only if a real tenant's list outgrows client-side filtering.
- **#7 [both clients] "Записать" deep-link** into the `26-268` manual flow with the person pre-recognized —
  depends on `26-268` landing; file when it does.
- Notes preview, block-link, erase, merge-hint — see §2 "kept off the hub" reasons; each its own future
  pass if wanted.

---

## 9. Deviations from the author's sketch (with reasoning)

- **Search is client-side in v1**, not a new endpoint — the name is already batch-fetched for the merge and
  the phone is on the row, so filtering the in-memory list needs no backend and works instantly; a server
  search is a scale concern this product does not have yet (zero real tenants). Recorded as a decision (§6).
- **Past/future is a filter on the list and a split in the detail**, not one global toggle — past-vs-future
  is a property of a booking, not a client, so the split belongs where the bookings are (the detail); the
  list gets the *С предстоящей записью* filter that actually matches the phone-operator's task. This answers
  the author's stated uncertainty about how to express it.
- **The warning glyph appears only in the neither-verified-nor-confirmed state** — a green tick on every
  confirmed row is noise; the glyph earns attention precisely because it is rare and actionable (it links to
  Подтвердить телефон). The two facts stay two facts on the wire and on the detail.
- **Two new reads, not one** — the bookings live in the calendar and the conversations in chat (`adr/0184`),
  and the client merges them; a single "client dossier" endpoint would force the server-to-server person read
  `adr/0184` decision 4 exists to forbid.
- **No new ADR** — every write is pre-existing; the reads follow `adr/0184`'s established display-merge.
  Contrast `26-268`, which needed `ADR-0188` for a new permission and new write semantics.
