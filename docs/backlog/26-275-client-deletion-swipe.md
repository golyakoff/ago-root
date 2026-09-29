# 26-275 · [design] Delete a client from Записи ▸ Клиенты (mirror: console + android)

- **Stage**: 26. Kind: research + design proposal + recommended ticket breakdown (this file is the design;
  the slices in §8 are filed as their own numbered items). Author need stated 2026-09-29.
- **Status**: proposed — not yet sliced into GitHub issues. This document is the research deliverable for
  the managing session to slice from. **It carries one genuine data-policy decision for the author (§2,
  the blast radius of "delete a client") and two smaller flags (§2 hard-vs-soft, §3 the disjoint-role
  implication) — presented as options with a recommendation, never decided silently.**
- **Repos touched by the feature**: `ago-calendar` (the erase-initiation write + future-bookings guard +
  `PersonErased` publisher), `ago-chat` (the `PersonErased` consumer that erases the Person, + the new
  `customer:erase` permission string and seed), `ago-console` + `ago-android` (the two operator surfaces).
  No platform change. Builds directly on the 26-269 redesign (the tappable Клиенты list and the
  client-detail hub) and reuses the merged per-person bookings read and the `booking:cancel` path.

## The need (author, verbatim intent, 2026-09-29)

- Swipe-to-delete a client in the Клиенты list (Записи ▸ Клиенты — the list redesigned in 26-269).
- **Admin-only** (only administrators may delete).
- If the client has **future bookings** → do **not** delete; explain that the operator must cancel those
  bookings first. **Consider giving a way to navigate to the future bookings to cancel them** (thought
  through and proposed in §5).
- If the client's bookings are all in the **past** (or none) → ask for confirmation, then delete.
- The swipe-to-delete **visual/interaction must be taken from Диалоги ▸ Все**
  (`ago-android/app/src/main/kotlin/ago/chat/android/conversations/ConversationListScreen.kt`).

---

## 1. What exists today (cited)

### 1.1 The Клиенты list and the client-detail hub (26-269)

The list is `Записи ▸ Клиенты`, tappable rows opening a **client-detail hub** — android
`ago-android/.../bookings/ContactsScreen.kt` (VM `ContactsViewModel.kt`, gated in `bookings/BookingsTab.kt`);
console `ago-console/src/pages/CalendarContactsPage.tsx` (`/calendar/contacts`). Both read the calendar's
`GET /contacts` → `Contact[]` (gated `customer:read`), display-merged with chat's Person name/emoji
(`GET /api/v1/persons?ids=`). The client-detail hub's **Предстоящие / Прошедшие** segments render the
**merged per-person bookings read** (below). This design adds a destructive action to that surface; it
introduces no new list or read.

### 1.2 The swipe interaction to mirror — Диалоги ▸ Все (cited exactly)

`ConversationListScreen.kt`'s `AllRow` / `EraseAction` / `EraseConfirmDialog` are the reference. The exact,
shipped mechanics (all values named in that file's own metrics block, each traced to the mockup CSS):

- **Hand-rolled reveal, not `SwipeToDismissBox`.** The row is a `Surface` translated by
  `Modifier.offset { IntOffset(animatedOffset, 0) }`, driven by `Modifier.draggable(Orientation.Horizontal)`
  whose delta is `coerceIn(-revealWidthPx, 0f)` — clamped to a **partial** reveal of exactly the action
  panel's width (`EraseActionWidth = 80.dp`, from `.swipe-del{width:80px}` / `.row.swiped{translateX(-80px)}`),
  the row still readable beside it. `AllRow`'s own doc comment states why the hand-rolled reveal is used
  over Material 3's full-width dismiss.
- **Two anchors, settled on release.** `onDragStopped = { offsetX = if (offsetX < -revealWidthPx / 2f)
  -revealWidthPx else 0f }` — past the halfway threshold it opens, else it snaps closed.
  `animateFloatAsState(label = "eraseReveal")` animates between the two.
- **The revealed panel** (`EraseAction`): a `Surface` filled `MaterialTheme.colorScheme.error` with
  `onError` content (the mockup's `--danger`), carrying the `AgoIcons.TrashForever` glyph
  (`EraseActionIconSize = 26.dp`) over a **two-line** caption (two `Text`s, never one string with a
  newline, so no font can wrap it), `EraseActionGap = 5.dp` between glyph and caption.
- **Confirmation between the swipe and the request** (`EraseConfirmDialog`): an `AlertDialog` with a title,
  a body, a danger-coloured confirm `TextButton` (`agoStatusColors().dangerText`) and a plain cancel. Its
  doc comment: "Erasure is irreversible on the server and a swipe is a gesture a pocket can perform — those
  two facts together are the whole argument for a dialog here."
- **Gated by capability, gesture not attached at all without it** (`26-90` posture): `val swipeable =
  canErase`; when false, the `draggable` modifier is simply not applied (`.then(if (swipeable) … else
  Modifier)`) and `LaunchedEffect(swipeable) { if (!swipeable) offsetX = 0f }` closes any open reveal on
  revocation. "Hide, don't disable" — an operator who cannot erase gets a row that behaves exactly like a
  «Мои» row.
- **Optimistic removal + recoverable failure** (`26-118`): confirming hands the id to
  `ConversationListViewModel.confirmErasure`, which drops the row from the list at once; a failed background
  erasure restores it and raises a non-blocking «Не удалось удалить» snackbar with a «Повторить» action
  that re-issues the request. Test hook `ERASE_ACTION_TEST_TAG`.

**This whole shape ports one-for-one to the Клиенты row.** The only differences are the caption («Удалить»/
«клиента» rather than «диалог»), the capability (`customer:erase` rather than `conversation:erase`), and
the branch on future bookings (§4/§6) — the reveal, the 80dp/halfway thresholds, the danger panel, the
`TrashForever` glyph, the confirm dialog and the optimistic-remove-with-retry are taken verbatim.

### 1.3 The person model — adr/0184 (what "a client" actually is)

`adr/0184` deleted the calendar's `customers` copy. **Chat owns the `Person` (elevated from `Visitor`) as
the account's single person registry** — display name, contact channels, creditworthy, reliability,
operator **notes about the person**, merge. **The calendar keeps only a thin `PersonRecord`**
(`ago-calendar/src/Ago.Calendar.Domain/PersonRecord.cs`) keyed by the opaque `PersonId` — phone, no-show
count, verified/operator-confirmed-phone facts rule 8 forces it to own — plus `Event.person_id` on each
booking. **No name, no notes** on the calendar side.

Every row in Записи ▸ Клиенты therefore has a **calendar `PersonRecord`** (the list comes from the
calendar's `GET /contacts`), and — because `PersonRegistered` is published on every booking mint (widget or
manual, 26-268) and consumed by chat's `RegisterExternalPersonHandler` to create a `Visitor`/Person — a
matching **chat Person**. A client can be a manual client (26-268) with a Person but **no conversation at
all**, or a chat-originated client with one or more conversations.

adr/0184's Consequences section already sketches the erasure shape this feature must build:

> "person erasure deletes one Person in chat and cascades the calendar's operational record + events by
> id. `personal-data.md` must be rewritten to this two-store, one-identity shape."

That sketch is a starting point, not a finished design — and §2 refines its *direction* for a reason the
sketch did not have to confront (the future-bookings guard is a rule-8 calendar fact).

### 1.4 The erasure machinery that exists (chat)

Chat has **conversation-scoped** and **site-scoped** erasure, both hard and request-driven, both in the
Worker:

- `Ago.Chat.Worker/ConversationErasureJob.cs` + `ConversationErasureQuery.cs`: a `BackgroundService` that
  claims conversations flagged `erasure_requested_at`, and for each one — in a deliberate order — deletes
  MinIO objects first, then messages in bounded batches, then attachments, then **the visitor's contact
  details and person-notes keyed to the visitor** (`DeleteContactDetailsForVisitorAsync`,
  `DeletePersonNotesForVisitorAsync` — already visitor-wide, not conversation-wide, adr/0184 O3), then the
  archive (`ConversationArchiveEraser`, 24-09), then the `erasure_records` receipt (24-13), then the
  conversation row. It never touches `visitor_restrictions` (25-78) and never deletes the `Visitor`/Person
  row itself.
- `Ago.Chat.Worker/SiteErasureJob.cs` + `SiteErasureQuery.cs`: whole-tenant teardown.

There is **no person-scoped erasure** today (a person can have several conversations; nothing loops them and
then deletes the Person row), and there is **no cross-repo erasure event** — nothing in the calendar tells
chat "erase this person", and nothing in chat tells the calendar "this person is gone." `personal-data.md`
inventories every store; its `visitors` / `visitor_contact_details` / `conversations` rows are the chat side
of a person, and the calendar's `person_records` + `events` are the other.

`grep` confirms: **no `PersonErased` / `PersonDeleted` contract, and no `person:erase` / `customer:erase` /
`customer:delete` permission exists in either repo today.**

### 1.5 The per-person bookings read — merged (26-269), reused for the guard

`ago-calendar/.../UseCases/PersonBookings/GetPersonBookingsHandler.cs` + `IPersonBookingReadStore` +
`GET /api/v1/console/contacts/{personId}/bookings` (`ConsoleEndpoints.cs`), gated `customer:read`. Returns
**`PersonBookingRow`** for this person's whole held history — held statuses only (`Booked`,
`PendingConfirmation`, `NoShow`; never `Cancelled`/`Available`) — each row carrying `StartsAt`, `EndsAt`,
`Status`, `BookingId`, `OriginConversationId`, service/worker. This is exactly the data the future-bookings
guard needs: **a future booking is `Status ∈ {Booked, PendingConfirmation}` AND `StartsAt > now`** (a
`NoShow` is by definition past; a `Cancelled` is not returned at all). No new read is required for the guard.

### 1.6 The cancel path — merged, for the navigate-to-cancel affordance

`ago-calendar/.../UseCases/BookingLifecycle/CancelBookingHandler.cs`, gated `Permission.BookingCancel`
(`booking:cancel`), transitions `Booked → Cancelled` (and `PendingConfirmation → Cancelled`), resolving the
whole run by `booking_id`. `booking:cancel` is seeded into the **Operator** role
(`RegisterSiteHandler.OperatorRolePermissions`). So the "cancel the future bookings, then delete" flow the
author asked for is composable entirely from existing writes — see §5. (Note the accepted product gap
CancelBookingHandler documents: a cancelled slot is not re-offered; irrelevant to erasure.)

### 1.7 The seeded roles are disjoint — a load-bearing fact for §3

`RegisterSiteHandler` seeds two roles whose permission arrays **do not overlap**: `OperatorRolePermissions`
holds `customer:read`, `customer:edit`, `booking:cancel`, `booking:reschedule`, the conversation actions;
`AdminRolePermissions` holds `site:configure`, `site:erase`, `conversation:erase`, `site:export`,
`calendar:configure`, `channel:manage`, … and **none of the Operator permissions**. Admin does **not**
inherit Operator. In practice a real administrator holds **both** roles — a pure-Admin cannot even open
Записи ▸ Клиенты (that list needs `customer:read`, an Operator permission). §3 turns on this.

---

## 2. What "delete a client" means — the erasure-mechanism decision (the crux)

Because adr/0184 collapsed the person to **one identity with one id**, there is no longer a separate
"calendar customer" object to delete in isolation — "a client" *is* the Person, split across two stores by
rule 8. So "delete a client" is a **person erasure**: a form of the GDPR erasure the 16-0x machinery already
implements, extended to the person as a whole and across the two products.

### 2.1 Decision — mechanism: person erasure, hard, **calendar-initiated**, cascading to chat via a new `PersonErased` outbox event

Recommended shape:

1. **Entry point and the guard live in the calendar.** The delete originates from the Клиенты list (a
   calendar surface). A new operator-authenticated endpoint on the calendar's console group —
   `DELETE /api/v1/console/contacts/{personId}` (or `POST …/{personId}/erase`) — (a) checks the new
   `customer:erase` permission (§3), (b) reads the calendar's own `events` for **future held bookings** for
   this person+tenant (`Status ∈ {Booked, PendingConfirmation} AND StartsAt > now`), and **refuses with a
   typed "has future bookings" error** if any exist (§4), (c) otherwise, in one transaction, deletes this
   person's `PersonRecord` and their held past/no-show `events`, and **stages a `PersonErased{personId,
   accountId}` outbox event** (rule 4 — the state change and the integration event commit together;
   publishing is the separate outbox step).
2. **Chat consumes `PersonErased` and erases the Person.** A new idempotent consumer (rule 5) flags every
   conversation of that visitor with `erasure_requested_at` (feeding the existing `ConversationErasureJob`,
   which already drains the visitor's contact-details and person-notes visitor-wide), and — once the
   person's conversations are drained — deletes the `Visitor`/Person row itself. The `Visitor` row goes
   **last**, the same "row after everything it owns" discipline `ConversationErasureQuery.DeleteConversationAsync`
   already follows, so a crash mid-erasure leaves a re-claimable flag rather than an orphan.

**Why calendar-initiated, against adr/0184's "chat deletes the Person and cascades the calendar" sketch.**
adr/0184 wrote the sketch before this feature's constraint existed. The **future-bookings guard is a
calendar fact**, and **rule 8** forbids a write decision (whether the erase may proceed) from reading a
remote service or a cache — it must be decided in the database that owns the fact. If chat initiated, chat
could not enforce the guard without a **server-to-server person/bookings read**, which adr/0184 decision 4
exists to forbid *and* which rule 8 forbids for a write gate. So the initiator must be the side that owns
the gating data — the calendar — and chat becomes the downstream consumer. This inverts the sketch's
direction, keeps every rule intact, and is precisely the kind of refinement that earns an ADR (§7).

**Why an integration event, not a synchronous cross-service delete.** The two products are independent
deployables (adr/0012/0027) with no server-to-server write path (adr/0184 decision 2/4). The person spans
both stores; the only rule-compliant way to cascade a cross-store delete is the outbox + at-least-once
consumer the whole system already uses (rules 4/5). The eventual-consistency window (calendar record gone,
chat Person catching up) is the same posture adr/0184 already accepts for the *creation* direction
(`PersonRegistered`).

### 2.2 Decision — hard vs soft: **hard (irreversible)**, recommended; soft offered as the alternative

Every erasure this system has is hard (`ConversationErasureJob`/`SiteErasureJob`; complete once adr/0050's
30-day backup window passes). adr/0184's own wording is "deletes one Person." **Recommend hard**, consistent
with the existing machinery and with the author's "then delete" phrasing.

> **AUTHOR FLAG (smaller).** A **soft** alternative exists: mark the `PersonRecord` (and Person) removed —
> hidden from the Клиенты list and every read — while retaining the rows, reversible. This would be a *new*
> pattern (nothing else here soft-deletes a person) and it contradicts adr/0184's "deletes" framing and the
> erasure-as-compliance posture. Recommended **against** unless the author specifically wants
> list-tidying-without-erasure, in which case it is a materially different (and simpler, calendar-only)
> feature that should not carry the word "delete" or the erasure machinery at all.

### 2.3 The blast radius — the one genuine data-policy decision for the author

> **AUTHOR DECISION (the real one).** "Delete a client" under one-identity (adr/0184) means erasing
> **everything the person is**, and for a chat-originated client that **includes their support-chat
> conversations, messages and attachments**, not only their booking record. Two readings:
>
> - **Option A — full person erasure (recommended).** Deleting a client erases the Person entirely: the
>   calendar `PersonRecord` + past bookings **and** the chat Person + all their conversations/messages/
>   attachments/notes/contact-details. This is what adr/0184's Consequences literally describe, it is the
>   only reading consistent with "one person, one id, one home," and it is a true erasure a tenant can point
>   to when a person asks to be forgotten. Cost: an operator tidying the booking list also destroys that
>   person's chat history — which is correct under one-identity but must be **named in the confirm dialog**
>   ("удалит клиента и всю историю переписки", §6), never silent.
> - **Option B — calendar-scoped forget (narrower).** Deleting a client removes only the calendar
>   `PersonRecord` + past bookings, leaving the chat Person and conversations intact. This is *not* an
>   erasure and re-booking would re-mint a record against the same Person; it leaves a half-deleted
>   identity, contradicts adr/0184, and answers "hide this from my booking client list" rather than "delete
>   this client." Recommended **against**, offered only because the author's surface is the booking list and
>   they may have meant the narrower thing.
>
> **Recommendation: Option A.** If the author wants B, it is the "soft, calendar-only" feature of §2.2's
> flag and should be renamed and de-scoped (no `PersonErased`, no chat change, no ADR).

The rest of this document assumes **A + hard + calendar-initiated**; where a choice would change under B it
is noted.

---

## 3. Permission — a new `customer:erase`, Admin-only, byte-for-byte in both products

**No `customer:erase` / `person:erase` / `customer:delete` exists today** (grep confirmed both repos). The
closest existing permissions are the wrong scope: `conversation:erase` (conversation-scoped) and
`site:erase` (whole-tenant) — both Admin-only, both destructive, and their `Permission.cs` remarks give the
exact granular-permission argument for adding a **third** distinct blast radius: person-scoped erasure is
neither one-conversation nor one-whole-account.

**Decision: add a new `customer:erase`, seeded to the Admin role only.**

- **Naming: `customer:erase`.** The `customer:*` prefix already names this entity in *both* products
  (`customer:read`, `customer:edit` exist byte-for-byte in `Ago.Chat.Domain.Permission` and
  `Ago.Calendar.Domain.Permission`), and `:erase` matches the verb the erasure permissions already use
  (`site:erase`, `conversation:erase`). `person:erase` was considered and rejected — there is no `person:*`
  prefix in the vocabulary, and introducing one for a single permission would fracture the naming the two
  products already share for this entity. (The reflection-derived `Permission.AllKnownValues` in chat picks
  the new field up automatically; the owner role-tool validates against it.)
- **Byte-for-byte in both `Permission.cs` files** (adr/0093: separate repos, wire-agreement, no shared
  type). The calendar's endpoint (§2 step 1a) checks `customer:erase`; chat's `PersonErased` consumer needs
  no permission check (it is a trusted internal event, the same posture `RegisterExternalPersonHandler` has
  for `PersonRegistered`). The string must exist in both because grants flow through the account-side role
  catalogue and are read via projection in each product.
- **Admin-only, the author's requirement.** Seed `Permission.CustomerErase.Value` into
  `AdminRolePermissions` (`RegisterSiteHandler`), the same Admin-only placement `site:erase`/
  `conversation:erase` already have. Do **not** add it to the Operator set. **Do not forget the other
  restatements** the erasure permissions' own remarks flag: `MintDemoTenantHandler.AdminRolePermissions`,
  and — since this is a *calendar-module* permission — `ago-deploy`'s
  `ModulePermissions__calendar__Admin__*` configuration (the "fourth restatement" gap 23-102/26-268 already
  document; a separate ago-deploy change, not reached by the handler).

> **AUTHOR FLAG (the disjoint-role implication, §1.7).** In this codebase "admin-only" means the Admin role,
> and Admin and Operator are **disjoint** — a pure-Admin holds neither `customer:read` (needed to open the
> Клиенты list) nor `booking:cancel` (needed to clear the future-bookings blocker, §5). So the person who
> deletes a client in practice holds **both** roles; the delete affordance is simply the extra
> `customer:erase` gate on top of the `customer:read` an operator-admin already has. This needs **no change
> to the disjoint-role model** — it is stated so the implementer seeds `customer:erase` into Admin (not
> Operator) and does not try to make it self-contained. If the author instead wants operators (not only
> admins) to delete, that is a one-line change of which role the string seeds into, but it contradicts the
> stated "admin-only" requirement.
- **Backfill.** Per 26-274 / `reference_entitlement_backfill_to_existing_sites`: existing tenants' Admin
  roles would need a re-grant→projection pass to gain a newly-added permission. **Zero real tenants today**
  (`zero_real_tenants_free_to_change_backend`, re-confirm before relying on it) → no backfill needed now;
  flag it if tenants exist at build time.

---

## 4. The future-bookings guard — server-side authoritative, client-side for UX

**Two layers, and the server is the authority (rule 8).**

- **Server-side (the real gate), in the calendar.** The erase-initiation endpoint (§2 step 1) reads the
  calendar's own `events` inside the request — **not** a cached or client-supplied count — for any
  `Status ∈ {Booked, PendingConfirmation} AND StartsAt > now AND person_id = @p AND tenant_id = @t`. If any
  exist, it refuses with a **typed error** ("client has N future bookings; cancel them first") and stages
  nothing. This is a new, tiny read (or a reuse of `IPersonBookingReadStore` filtered to the future subset)
  living beside the erase handler, so the gate is decided in the database that owns the fact — rule 8 in the
  same shape the atomic booking claim already uses (a compare-and-set whose verdict is the DB's, never a
  cache's). The `NoShow`/`Cancelled` states can never block a delete (no-show is past; cancelled is not
  returned) — only genuine upcoming appointments do.
- **Client-side (UX only), on both surfaces.** The client-detail hub already holds the merged per-person
  bookings (§1.5), so the client knows the future count without a new call. It uses that to **branch the
  swipe/action before confirmation** (§6): past-only → the delete-confirm dialog; future-present → the
  explain-and-navigate state. The client-side branch is a courtesy that avoids a doomed round-trip; if the
  client's data is stale and it lets a delete through, the **server refuses** and the same explain state is
  shown from the server's typed error. Never trust the client for the gate.

---

## 5. The "navigate to the future bookings to cancel them" affordance (the author asked to consider this)

**Proposed, and it composes entirely from existing writes.** The client-detail hub (26-269 §4) already lists
**Предстоящие** with per-booking rows, and `booking:cancel` + `CancelBookingHandler` already cancel a
confirmed or pending run (§1.6). The design:

1. From the **blocked-delete** state (future bookings present, §6), the primary action is **«Перейти к
   записям»** → it opens (android) / scrolls to (console) the client-detail hub's **Предстоящие** segment.
2. **Each upcoming booking row carries a «Отменить» (cancel) action**, gated `booking:cancel`, calling the
   existing `CancelBookingHandler` (`Booked`/`PendingConfirmation → Cancelled`). This is a small reuse; if
   the client-detail Предстоящие segment does not yet render a per-booking cancel control (26-269 §4 named
   reschedule explicitly, cancel only implicitly), **adding it is part of this feature's UI slice**, not a
   new backend.
3. Once every future booking is cancelled, the client has only past/`NoShow`/no bookings and becomes
   deletable — the operator returns to the list (or the same detail) and the delete now passes the guard.

> **Practical note tied to §3's disjoint-role flag.** Cancelling needs `booking:cancel` (Operator role); an
> operator-admin (who by §3 already holds both roles) can do the whole "cancel then delete" flow
> self-service. A pure-Admin could delete but not cancel — another reason the deleter holds both roles in
> practice. No code change needed; just do not gate cancel behind `customer:erase`.

We deliberately do **not** build an "erase and auto-cancel the future bookings" shortcut: cancelling a
confirmed appointment is a customer-affecting act (CancelBookingHandler's own remarks — a slot planned around
"possibly for weeks") that must be a deliberate, separately-permissioned operator decision, not a silent
side effect of tidying a list. The guard-plus-navigate flow keeps that decision explicit.

---

## 6. The two clients' UX

### 6.1 Android — swipe, mirroring Диалоги ▸ Все exactly

On the Клиенты row (`ContactsScreen.kt` / `ContactCard`), port `AllRow`'s mechanism verbatim (§1.2): the
hand-rolled 80dp partial reveal via `Modifier.draggable`, the halfway settle, the danger `Surface` panel
with `AgoIcons.TrashForever` and a two-line caption **«Удалить» / «клиента»**. Gated on a new
`canEraseClient` capability (`customer:erase`), threaded from `AppShellScreen`'s permission set the identical
way `canEraseConversations`/`canConfigureSite` already are — **gesture not attached at all** without it
(`.then(if (swipeable) … else Modifier)` + the revoke-closes-reveal `LaunchedEffect`). All new strings as
resources, both languages (`feedback_android_strings_must_be_resources`).

On the confirm tap the panel branches on the future-booking state (client-side, §4):

- **Past-only / none → `EraseConfirmDialog` equivalent.** An `AlertDialog`, danger confirm text
  (`agoStatusColors().dangerText`) + cancel, whose **body names the blast radius** (Option A): e.g. «Удалит
  клиента, историю записей и всю переписку. Отменить нельзя.» Confirm → the calendar erase endpoint;
  **optimistic removal + «Не удалось удалить»/«Повторить» snackbar** on failure, exactly the 26-118 shape.
- **Future present → a distinct blocked state.** Not the delete-confirm dialog: an `AlertDialog` (or the
  panel expands) reading «Нельзя удалить: есть предстоящие записи», explaining the operator must cancel them
  first, with a primary **«Перейти к записям»** button (§5) and a cancel/dismiss. If the server refuses a
  delete that slipped through, show this same state from the typed error.

### 6.2 Console — the desktop equivalent, **not** a swipe (26-272 lesson)

Mirror the *intent*, not the gesture (26-272 "don't import mobile IA"). Add a destructive **«Удалить
клиента»** control — in the client-detail header overflow (`⋮`) or as a row action — **visible only to
`customer:erase` holders** (hide, don't disable). It opens the same two-branch flow:

- **Past-only / none →** a confirm dialog naming the blast radius (Option A wording), destructive-styled
  confirm → the calendar erase endpoint → reload/remove the row.
- **Future present →** a dialog explaining the blocker with a link/scroll to the detail's **Предстоящие**
  section, where each booking has a **«Отменить»** action (§5). The server remains the authority.

i18n both languages; page test + fixture; `typecheck && lint && test && ux-gate` green (a DTO/endpoint shape
change can break a stale fixture, `feedback_ago_console_full_command_set_includes_ux_gate`).

**Mockup.** Not built as a separate `ago-android-design` page — the swipe visual is already pixel-specified
and shipped in `ConversationListScreen.kt` (§1.2), and this design reuses it unchanged, so a new mockup would
duplicate it and carry the Dockerfile-COPY-line 404 risk (`#19`) for no new pixels. The three states
(swipe-reveal, confirm-past-with-blast-radius-wording, block-future-with-«Перейти к записям») are specified
above precisely enough to build from. If the author wants a rendered mockup, add it to `ago-android-design`
*with* its `COPY` line and `index.html` nav card/TOC entry (a page 404s without the COPY).

---

## 7. ADR need — yes: ADR-0189

This clears the "decision worth arguing about" bar (CLAUDE.md), on four counts, none of which any existing
ADR already settles:

- a **new integration event** `PersonErased` (a new messaging contract, versioning/idempotency, adr/0006
  semantics);
- a **new permission** `customer:erase` with a new (person-scoped) blast radius;
- **new write semantics** — a person-scoped erasure that is **calendar-initiated with a future-bookings
  precondition** and cascades cross-repo via the outbox, plus chat's first **person-scoped** (not
  conversation- or site-scoped) erasure;
- an explicit **refinement of adr/0184's erasure direction** (calendar-initiated, not chat-initiated),
  justified by rule 8 and adr/0184 decision 4.

Draft **ADR-0189** (next free; highest is 0188), landed in the same change as the calendar backend slice
(§8 #2). Draft core:

- **Context**: adr/0184 collapsed the person to one identity across two stores; operators need to delete a
  client from the booking list; the delete must refuse while future bookings exist (a rule-8 calendar fact),
  and must not create a server-to-server person read.
- **Decision**: deleting a client is a **hard person erasure**, **initiated in the calendar** (which owns the
  future-bookings gate), refusing on any future held booking, deleting its own `PersonRecord` + past events
  and staging `PersonErased{personId, accountId}`; **chat consumes `PersonErased`**, flags the person's
  conversations for the existing `ConversationErasureJob` and deletes the `Visitor`/Person row last; gated
  on a new Admin-only `customer:erase`.
- **Alternatives weighed**: (a) chat-initiated per adr/0184's sketch — rejected, cannot enforce the guard
  without a forbidden cross-product read / rule-8 violation; (b) calendar-only "forget" leaving chat intact
  (§2.3 Option B) — rejected, half-deleted identity, not an erasure; (c) soft delete/tombstone (§2.2) —
  rejected, new pattern, contradicts "deletes"; (d) synchronous cross-service delete — rejected, no
  server-to-server write path (adr/0012/0184); (e) auto-cancel future bookings on delete (§5) — rejected, a
  customer-affecting act must stay a deliberate, separately-permissioned decision.
- **Consequences**: `personal-data.md` gains the person-erasure path spanning both stores; the calendar
  gains an erase endpoint + future-bookings gate; a new outbox event and a new idempotent chat consumer; the
  eventual-consistency window between the calendar record's deletion and the chat Person's teardown (the
  `PersonRegistered` posture in reverse); `customer:erase` seeded Admin-only in three/four restated places.

---

## 8. Recommended ticket breakdown (one ticket = one promise that lands green — rule 15)

Filed as their own numbered items; mirror console + android per the "full console parity" standard.

1. **[cross-repo: ago-chat + ago-calendar] Add `customer:erase` permission and seed it.** Identical
   `new("customer:erase")` in both `Permission.cs` (byte-for-byte), seeded into the **Admin** role in
   `RegisterSiteHandler.AdminRolePermissions` and `MintDemoTenantHandler.AdminRolePermissions`, plus the
   `ago-deploy` `ModulePermissions__calendar__Admin__*` restatement. One worker owns the whole contract
   (`feedback_one_worker_per_cross_repo_task`). One promise: the capability exists in both products and only
   the Admin role holds it. No backfill while zero real tenants.
2. **[ago-calendar] Client-erase write + future-bookings guard + `PersonErased` publisher + ADR-0189.** New
   use case + `DELETE /api/v1/console/contacts/{personId}` (gated `customer:erase`): refuse on any future
   held booking (typed error); else, in one transaction, delete the `PersonRecord` + this person's held past
   events and stage `PersonErased` (rule 4); unit + integration tests (past-only deletes, future-present
   refuses, wrong-tenant is a no-op/empty). ADR-0189 in the same change. **Migration lane** iff a schema
   change is needed (likely none — deletes existing rows; confirm). One promise: an admin POSTs a delete, a
   client with only past bookings is erased calendar-side and `PersonErased` is published, a client with a
   future booking is refused.
3. **[ago-chat] `PersonErased` consumer — person-scoped erasure.** New idempotent consumer (rule 5): flag
   every conversation of the person's visitor for the existing `ConversationErasureJob`, and delete the
   `Visitor`/Person row after they drain (row last). Contract `PersonErased` added to `Ago.Calendar.Contracts`
   and consumed in chat (messaging-contract skill; versioning). Integration test: a `PersonErased` erases the
   Person, its conversations, contact-details, person-notes. One promise: consuming `PersonErased` erases the
   whole chat side of the person. Depends on #2's contract.
4. **[ago-console] Delete-client action + guard UI.** On the client-detail hub / row (`CalendarContactsPage`),
   `customer:erase`-gated «Удалить клиента»: past-only confirm (blast-radius wording) → the calendar endpoint
   → remove/reload; future-present → explain + link to Предстоящие with a per-booking «Отменить»
   (`booking:cancel`) if not already present. `createClientErase`/`cancelBooking` in `calendarApi.ts`, i18n
   both languages, page test + fixture, `ux-gate` green. One promise: an admin deletes a past-only client and
   is blocked-with-navigate on a future-booked one. Depends on #2 (and #5's cancel control if shared).
5. **[ago-android] Swipe-to-delete client + guard UI.** On `ContactsScreen.kt`: port `AllRow`'s swipe verbatim
   (§1.2), gated on a new `canEraseClient` (`customer:erase`) threaded from `AppShellScreen`; past-only →
   confirm dialog (blast-radius wording) + optimistic-remove/retry-snackbar (26-118 shape); future-present →
   blocked state with «Перейти к записям» → client-detail Предстоящие with per-booking «Отменить». All strings
   as resources both languages; VM + tests. One promise. Depends on #2.

**Order:** #1 → #2 (+ADR) → #3 (needs #2's contract) can run alongside #4/#5 (both consume #2's endpoint; the
per-booking cancel control in the detail is shared, build it once in whichever of #4/#5 lands first or split
it out). #4/#5 can start their guard UI against a stubbed endpoint but land after #2.

**Deferred / notes (not v1 slices):**
- If the author picks **Option B** (§2.3), this collapses to a single calendar-only "remove from client
  list" item — no `customer:erase` blast-radius argument, no `PersonErased`, no chat change, no ADR — and
  should be renamed off the word "delete."
- `personal-data.md` update (the person-erasure path) rides ADR-0189's change (#2) as part of the
  deliverable, per "docs are part of the deliverable."

---

## 9. Deviations from the author's sketch, and the decisions surfaced (with reasoning)

- **The swipe is mirrored exactly on android and deliberately *not* on console** — 26-272's "don't import
  mobile IA" lesson: console gets an admin-gated destructive button with the same two-branch guard, mirroring
  the intent, not the gesture.
- **"Delete a client" is a person erasure, not a calendar-only row removal** — adr/0184 left one identity, so
  the only coherent "delete" erases the Person across both stores (§2.3 Option A). The narrower reading is
  surfaced as an explicit author decision, not assumed.
- **Calendar-initiated, inverting adr/0184's chat-initiated sketch** — because the future-bookings guard is a
  rule-8 calendar fact and a chat-initiated delete would need a forbidden cross-product read (§2.1). This is
  the ADR's central refinement.
- **A new `customer:erase`, Admin-only, over reusing `conversation:erase`/`site:erase`** — a third, distinct
  (person-scoped) blast radius, the same granular-permission reasoning those two permissions' own remarks
  already state (§3).
- **The guard is enforced server-side authoritatively; the client-side branch is UX only** — rule 8: a write
  gate reads the owning database, never a cache or a client-supplied count (§4).
- **Navigate-to-cancel composes existing writes; no auto-cancel** — cancelling a confirmed appointment is a
  deliberate, `booking:cancel`-permissioned, customer-affecting act, never a silent side effect of a delete
  (§5).
- **Three author-facing decisions are surfaced, not decided**: the blast radius (A vs B, §2.3 — the real
  one, recommend A), hard-vs-soft (§2.2 — recommend hard), and the disjoint-role practicality (§3 — no code
  change, stated so the seed lands in Admin).
