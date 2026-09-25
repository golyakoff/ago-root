# 26-111 · Android thread contact-detail / visitor-info panel — design & scoping

- **Stage**: 26 (Android app)
- **Kind**: design/scoping pass. No production code. The deliverable is this spec plus a proposed
  breakdown into implementation tickets (`26-112`…) for the author to approve.
- **Item**: `docs/backlog/26-111-design-the-android-thread-contact-detail-panel.md`
- **Mockup (agreed target)**: the contact-detail bottom sheet the author posted (Лиса · Апельсин —
  КОНТАКТНЫЕ ДАННЫЕ with Телефон/Почта «Показать», Имя «Недействительно», tags, «Заметки команды»,
  «Прошлые диалоги», «Приём файлов от посетителя», «Закрыть диалог»/«Ограничить»). The image asset that
  was committed under `docs/design/assets/26-111-thread-contact-detail-mockup.jpg` was the wrong
  screenshot (it was the Записи overflow mockup) and has been removed; the author will re-attach the real
  contact-detail mockup. This doc is built against the textual description, which task and backlog agree on.
- **Author's overriding principle**: the mockup is the agreed design. Where the current API cannot
  deliver a mockup element, the design proposes **how to change the API** to deliver it — never a
  "skip it because the API lacks it" compromise. UX comes first; the API bends to the mockup.

---

## 0. Blocking discrepancy — the mockup file on disk does not match the described design

**Read this first.** The image currently at
`docs/design/assets/26-111-thread-contact-detail-mockup.jpg` (a 1220×780 landscape Android
screenshot, EXIF `2026-09-25 08:11`) does **not** show the contact-detail bottom sheet. It shows the
**«Записи» (bookings/records) list screen** — a segmented control «Ожидают | Утверждены | Клиенты»,
the subtitle «Всё подтверждается автоматически.», an «AG» avatar, and a hand-drawn orange arrow +
circle highlighting the ⋮ overflow menu at the top-right. That is a different screen from a different
part of the app.

This is not a small thing: the mockup is described in the task and in the backlog item as the
*agreed, effort-intensive target*, and the file that is supposed to carry it carries something else.
This design is therefore built against the **textual paraphrase** — which is detailed and identical
between the task brief and the backlog item — and every element below is traceable to that paraphrase,
not to the image. **Before any `26-112`+ implementation ticket is opened, the author must replace the
asset with the real contact-detail mockup and this doc must be re-checked against it.** Two elements
in particular can only be pinned down from a real image and are flagged as product questions below:
(a) whether «Недействительно» on the Имя row is a settable state or a display label, and (b) the exact
layout/interaction of «Ограничить».

*(Teaching note: surfacing the contradiction rather than silently designing around it is CLAUDE.md's
instruction-source boundary applied to a tool result — the image is data, and when data contradicts
the stated intent, the honest move is to name it and ask, not to pick one and proceed.)*

---

## 1. Element-by-element map (mockup → real data source today)

Every row states the backing endpoint/hub method that exists **today** on the console/backend, or
**GAP** where none does. "Android client" = whether `ago-android` already has a port/adapter for it.

| # | Mockup element | Backend source today | Android client today | Status |
|---|---|---|---|---|
| H1 | Header avatar (emoji creature + food) | `ConversationSummaryDto.EmojiCreature/EmojiFood` (queue row) | `ConversationSummary.emojiCreature/emojiFood` (26-10) | **EXISTS** |
| H2 | Header localized name | `ConversationSummaryDto.VisitorName` (a `Name` contact-detail row), else localized emoji-pair label «Сова · Клубника» (`visitorEmoji.ts#visitorLabel`) | `ConversationSummary.visitorName`; **no** localized emoji-name dictionary yet | **PARTIAL** (name exists; emoji-name fallback dictionary is new on Android) |
| H3 | State chip «В работе» | `ConversationSummaryDto.State` (`"Assigned"`) | `ConversationSummary.state` (26-40) | **EXISTS** |
| H4 | "Первый визит 14 марта" | `Domain.Visitor.FirstSeenAt` exists in the DB (`visitors.first_seen_at`) but is **projected onto no wire DTO** | none | **GAP** (projection only) |
| H5 | "· N диалог(ов)" | No per-visitor total-conversation-count field exists anywhere; visitor-history is (a) gated on channel identity and (b) a keyset page, so its length is not a total | none | **GAP** |
| C1 | «КОНТАКТНЫЕ ДАННЫЕ» Телефон/Почта, masked | `GET /api/v1/conversations/{id}/contact-details` (`ListVisitorContactDetailsHandler`); `kind`∈`Phone/Email/Name`, `masked` flag | none | **EXISTS backend, no Android client** |
| C2 | «Показать» reveal (phone/email) | `POST /api/v1/conversations/{id}/contact-details/{id}/reveal` (`RevealVisitorContactDetailHandler`); `conversation:read` | Calendar-side reveal pattern only (`BookingsApi.revealCustomerPhone`, 26-53) — different endpoint | **EXISTS backend, no Android client** (reuse the reveal *pattern*, not the calendar endpoint) |
| C3 | Имя «Недействительно» when unverified | `Name` row exists; the caption "оператор ещё не подтвердил эти данные" is `contactDetailsCaption`. **Assessment (`Confirmed`/`Invalid`) is refused server-side for `Name`** — only `Phone`/`Email` are assessable | none | **PARTIAL / product question Q1** |
| C4 | Field caption "оператор ещё не подтвердил эти данные" | `contactDetailsCaption` (display string only) | none (new string resource) | **EXISTS (copy only)** |
| T1 | Conversation tags «Оплата»/«Срочно» | `GET /api/v1/conversations/{id}/tags` (`19-02`, each carries `source` Operator/Ai) | none | **EXISTS backend, no Android client** |
| T2 | «+ метка» add-a-tag | site vocabulary `GET /api/v1/sites/{siteId}/tags` + apply `POST /conversations/{id}/tags/{tagId}` / remove `DELETE …` (`18-04`); write gated `conversation:tag` | none | **EXISTS backend, no Android client** |
| N1 | «Заметки команды» count → | `GET /api/v1/conversations/{id}/notes` (`18-04`); **no count endpoint — count = list length**; read `conversation:read`, write `conversation:note_write` | none | **EXISTS backend (count via list), no Android client** |
| P1 | «Прошлые диалоги» count → | visitor-history: `OperatorHub.GetVisitorHistoryAsync` / `GetVisitorHistoryConversationAsync` (`18-07`). **Gated on `hasChannelIdentity`** (widget-only visitors get an empty list) and keyset-paged (length ≠ total) | none (hub has join/history/team methods only) | **EXISTS backend (gated), no Android client** |
| F1 | «Приём файлов от посетителя» toggle | write: `POST /conversations/{id}/grant-attachment-upload` / `…/revoke-attachment-upload` (`23-78`); state: `ConversationSummaryDto.HasAttachmentUploadGrant` + `…GrantedAt` + `…GrantedByOperatorId`; gated `conversation:attachment_upload_grant` | read flag only: `ConversationSummary.hasAttachmentUploadGrant` (26-15). **No write client** | **EXISTS backend + read flag, no Android write client** |
| A1 | «Закрыть диалог» | `POST /api/v1/conversations/{id}/close` (`6-02`, `closeConversation`); gated `conversation:close` | none (Android has claim/markRead/erase, not close) | **EXISTS backend, no Android client** |
| A2 | «Ограничить» (restrict visitor) | `POST /api/v1/conversations/{id}/block-visitor` (indefinite site-wide block, `23-77`, gated `conversation:block`) and/or `POST /conversations/{id}/close-as-spam` (close + mute window, gated `conversation:mark_spam`). Reversal: `POST /api/v1/visitor-restrictions/{visitorId}/lift` | none | **EXISTS backend, no Android client** (which action(s) — product question Q2) |

### What is genuinely already true on the backend (so no ticket rebuilds it)

Contact details (list/reveal/edit/assessment), conversation tags (list/apply/remove + site vocab),
team notes (list/add), visitor history (list + open-one), the attachment-upload grant
(grant/revoke + state fields), close, block-visitor, close-as-spam, and lift-restriction **all exist
as `ago-chat` REST endpoints / hub methods with the console already consuming them.** The Android work
is overwhelmingly *new client adapters over existing contracts*, plus the small number of true backend
gaps in §2.

---

## 2. Gaps — and the concrete API change that closes each (no "skip it")

### GAP-1 — "Первый визит {date}" (H4): `Visitor.FirstSeenAt` is not on any wire DTO

The datum exists in the domain and the DB (`Ago.Chat.Domain.Visitor.FirstSeenAt`,
`visitors.first_seen_at`) but is projected onto nothing the console or Android can read.

**Proposed change (ago-chat):** expose it. Two shapes, pick one in §5-Q3:

- **Option A (preferred): a new read endpoint** `GET /api/v1/conversations/{id}/visitor-summary`
  returning a small `VisitorSummaryDto { visitorFirstSeenAt, conversationCount, … }` — see GAP-2,
  which this same endpoint also closes. New `IConversationReadStore.GetVisitorSummaryAsync` (Dapper
  read model, `adr/0004`), a use-case handler gated on `conversation:read` + the per-conversation
  "is this operator on it" check every other operator-scoped read here uses, an `Ago.Chat.Api`
  endpoint, and a `Ago.Chat.Contracts` DTO. **Size: S–M** (one read query, one handler, one endpoint,
  one contract; no migration — the columns already exist).
- **Option B: grow `ConversationSummaryDto`** with `VisitorFirstSeenAt` (additive/nullable, the same
  discipline every field on that record already follows). Cheaper to add but it rides the queue read,
  which is polled and paginated — it makes every queue row carry a per-visitor fact only the open
  thread needs. **Size: S**, but architecturally noisier.

*(Teaching note: Option A keeps the queue DTO honest — the queue lists conversations, it does not
describe visitors; a per-visitor fact belongs on a per-visitor read. Its own doc comment already
resisted exactly this kind of accretion for `26-90`'s conversation-count.)*

### GAP-2 — "· N диалог(ов)" (H5): no per-visitor conversation count, and none at all for widget visitors

`26-90` deliberately declined a site-wide "how many conversations" count (a `COUNT(*)` over all
history, unbounded). But a **per-visitor** count is a different, bounded question, and the mockup shows
it unconditionally — including for an ordinary widget visitor, who has **no** `ChannelIdentity` and so
gets an empty visitor-history today.

**Proposed change (ago-chat):** return `conversationCount` for the visitor behind the open
conversation, site-scoped, counting all states, from the `visitor-summary` endpoint proposed in
GAP-1 (Option A). It is bounded by one visitor's own conversations (indexed by
`(site_id, visitor_id)`), not by the whole site, so it avoids the exact cost `26-90` rejected. If §5-Q4
decides the count should exclude `Pending`/erased rows, that is a `WHERE` clause on the same query.
**Size: folded into GAP-1's endpoint (no extra ticket if built together).**

### GAP-3 — «Прошлые диалоги» (P1) is invisible for widget-only visitors

Visitor-history short-circuits to `hasChannelIdentity=false → empty` for any visitor with no channel
identity (`GetVisitorHistoryHandler`, by design in `18-07`/`14-01`). Most AGO Chat visitors are
widget-only, so for most conversations the mockup's «Прошлые диалоги (N)» would always read 0 and open
nothing — which contradicts a mockup that shows it as a first-class row.

**Proposed change (ago-chat):** widen "past dialogs" to mean *this visitor's other conversations on
this site*, not *this channel-identity's conversations*. The read store already keys on
`visitor_id`; the only thing gating widget visitors out is the `channelIdentities.FindMostRecent…`
short-circuit. Replace that gate with the same per-visitor scoping the count uses. Because this is a
genuine widening of "which past messages an operator may open," it must be reflected in
`docs/architecture/personal-data.md` (the doc already tracks the cross-conversation-history read) and
almost certainly wants an ADR (it changes an authorization boundary, `adr/0016` territory).
**Size: M** (read-store query already exists; the change is the gate + the access-record/ personal-data
reasoning + tests). **Product question Q5 governs whether we widen at all or keep P1 channel-only.**

### GAP-4 — Имя «Недействительно» (C3): `Name` rows are not assessable

The backend refuses `SetVisitorContactDetailAssessment` for any kind but `Phone`/`Email`
(`assessable()` in the console mirrors a real server rule). So a literal «Недействительно» *state* on
the Имя row cannot be set today.

**Two readings, decided in §5-Q1:**

- **Reading A (no API change):** «Недействительно» is a **display label for the unverified/unconfirmed
  name**, i.e. the console's existing caption "оператор ещё не подтвердил эти данные" rendered as a
  small pill on the row. Delivered entirely in the Android UI + a string. **Size: none beyond the
  contact-details client.**
- **Reading B (API change, ago-chat):** the author wants the operator to be able to *mark a name
  invalid*. Then extend `VisitorContactDetailAssessment` to accept `Name` (domain rule change in
  `Domain.VisitorContactDetail.SetAssessment` + handler + the console's `assessable()` + tests). No
  migration (the `assessment` column already exists). **Size: S–M**, but it changes a domain invariant
  and so wants a line in the ADR/contact-details doc.

### Not a gap (worth stating, because it looks like one)

The «Приём файлов от посетителя» toggle (F1) **is** backed — `grant/revoke-attachment-upload` (23-78).
Android already reads `hasAttachmentUploadGrant`; only the two write calls and the toggle UI are new.

---

## 3. Built vs new on Android

### Reusable as-is
- **`ConversationSummary`** (`:core:domain`) already carries `emojiCreature/emojiFood`, `visitorName`,
  `state`, `hasAttachmentUploadGrant`, `createdAt` — H1, H2 (name half), H3, and the F1 read state.
- **The reveal *pattern*** — `RevealPhoneResult { Revealed/Refused/Failed }`, "server sends the
  unmasked value, never unmasked client-side," masked-stays-on-failure (`BookingsApi.revealCustomerPhone`,
  26-53). Reuse the **shape**, not the calendar endpoint.
- **The write-result vocabulary** — `BookingActionResult`/`ClaimResult { Succeeded/Refused/Failed }`
  and `NetworkFailure` classification — for close/block/grant/tag/note writes.
- **`Permission` constants object** (`:core:domain`) — extend with the new names; gating is
  hide-not-disable, exactly as `CloseConversationButton`/`BlockVisitorButton` do in the console.
- **`OperatorHubConnection`** for opening past-dialog history (`joinConversation`/`loadOlderHistory`
  return `HistoryPage`) — the visitor-history hub methods are new but sit beside these.
- **`Thread`/message rendering** (`ThreadScreen`, `MessageDto`) for read-only past-dialog display —
  the console reuses its own `Thread` component for exactly this (`VisitorHistoryPanel`).
- **`ThreadScreen`/`ThreadViewModel`/`ThreadUiState`** as the host the sheet opens over.

### Genuinely new on Android
- A **chat contact-details client** (`ContactDetailsApi` port + `KtorContactDetailsApi`): list + reveal
  (+ edit/assessment if in scope). New — the existing reveal client is calendar-only.
- A **conversation-tags client** (list applied, list site vocab, apply, remove).
- A **conversation-notes client** (list, add).
- A **visitor-history client** on Android (list + open-one) — the hub methods and/or REST.
- **Close / block-visitor / close-as-spam / grant-toggle** write calls on the Android
  `ConversationsApi` (or a new sibling port).
- A **`visitor-summary` client** for H4/H5 (per GAP-1/2).
- A **localized emoji-name dictionary** (H2 fallback «Сова · Клубника») — the console has
  `visitorEmojiNames`; Android needs its own resource-backed equivalent.
- The **bottom-sheet UI** itself and all its string resources (both locales — 26-91 rule: no literal
  strings).
- New **`Permission` constants**: `conversation:tag`, `conversation:note_write`, `conversation:close`,
  `conversation:block`, `conversation:mark_spam`, `conversation:attachment_upload_grant`
  (`conversation:read`/`conversation:send` are already implied; add where missing).

---

## 4. Mobile interaction spec

Grounded in the paraphrase (a bottom sheet over the open thread). Confirm against the corrected mockup.

### Opening
- The sheet is opened from **`ThreadScreen`** — a header affordance on the thread app bar (an "info"
  action or a tap on the visitor identity block). It is a **modal bottom sheet** (Material 3
  `ModalBottomSheet`), draggable, dismiss by drag-down / scrim tap / back gesture. It does not block
  the live conversation underneath from receiving pushes.
- The sheet is scoped to the **currently open conversation**; it is handed the `ConversationSummary`
  the thread already holds (H1–H3, F1-state — no extra round trip for those), and fires its own reads
  for contact-details, tags, notes counts, visitor-summary, and past-dialog count on open.

### Loading / empty / error, per section (mirroring the console's per-panel posture)
- **Each section loads independently** with a skeleton, so a slow visitor-history read never blocks
  contact details. The console draws exactly this per-panel skeleton/alert/empty split.
- **Empty**: contact details → "нет контактных данных"; tags → "меток нет"; notes count → 0 with the
  row still tappable to add; past dialogs → 0 (and, per Q5, either "нет прошлых диалогов" or the row is
  hidden for a widget visitor).
- **Error**: an inline, per-section retry — never a whole-sheet failure. Transport vs. server
  classification via the existing `NetworkFailure` vocabulary.
- **Refusal (permission)**: sections/actions the operator lacks the permission for are **hidden, not
  disabled** — the console's uniform rule. A server refusal on a write (e.g. reveal not entitled,
  close race lost) shows the **server's own `detail`** inline via the `Refused` arm; the masked value
  or prior state stays on screen.

### Per-action confirmation shape on a phone
- **Reveal (C2)**: single tap, no dialog (reveal is `conversation:read`-level, not destructive). The
  row is replaced in place by the server's unmasked response. A reveal is audited server-side.
- **Attachment toggle (F1)**: single tap, no dialog — reversible, the console's `SeatToggleButton`
  shape. Shows "granted by … · {time}" caption when on.
- **Add tag (T2)**: a picker sheet/menu of the site vocabulary minus already-applied; remove is an ×
  on the chip. `conversation:tag`-gated.
- **Add note (N1)**: tapping the «Заметки команды» row opens a notes sub-screen (list + composer);
  `conversation:note_write` gates the composer only.
- **Past dialogs (P1)**: tapping the row opens a list of the visitor's prior conversations; tapping one
  opens it **read-only** in the existing thread/message renderer (no composer, no actions) — the
  console's `VisitorHistoryPanel` behaviour. Q6 decides read-only vs openable-to-act.
- **Close (A1)**: **confirmation dialog** ("Закрыть диалог?") — it ends the operator's work item and
  drops the row from their rail. On success the sheet dismisses and the thread returns to the queue.
- **Restrict (A2)**: **confirmation dialog**, and its content depends on Q2 (single "block visitor
  indefinitely" vs a choice of block / close-as-spam). Destructive-styled. Reversal (lift) is not on
  this sheet — it lives in an admin restrictions screen (the console keeps lift separate too).

---

## 5. Product questions (not decided here — CLAUDE.md rule 14 "file as the question")

**Q1 — Имя «Недействительно»: display label or settable state?**
- *Option A* — a display label for "unverified name" (the existing caption as a pill). Cost: **0**
  backend; pure Android UI + string.
- *Option B* — a real, operator-settable Invalid on the name. Cost: **S–M** ago-chat domain change
  (allow `Name` in `SetAssessment`), console parity, ADR line. Changes a domain invariant.
- *Recommendation to weigh*: A, unless the author specifically wants operators to flag bad names.

**Q2 — «Ограничить» on mobile: which action(s)?**
- *Option A* — one action = `block-visitor` (indefinite site-wide block; `conversation:block`).
  Simplest; matches the console's `BlockVisitorButton`. Does not close the conversation.
- *Option B* — offer both `block-visitor` and `close-as-spam` (close + mute window;
  `conversation:mark_spam`) as a choice in the confirm sheet.
- *Cost*: A is one write client; B is two writes + a choice UI + explaining the difference on a phone.
- *Consideration*: two overlapping destructive verbs on a small screen is a comprehension risk.

**Q3 — Header facts delivery: new `visitor-summary` endpoint (Option A) or grow `ConversationSummaryDto`
(Option B)?** Cost: A = one clean new read (S–M), architecturally tidy; B = S but loads a
per-visitor fact onto the polled, paginated queue DTO. Recommendation: A.

**Q4 — What does "N диалог(ов)" count?** All conversations for the visitor on this site, or exclude
`Pending` (never-written) and erased rows? Cost: a `WHERE` clause either way; the question is what the
number should *mean* to an operator. (The console's own history panel filters `Pending` out as "not
real history.")

**Q5 — Past dialogs for widget-only visitors: widen, or keep channel-only?**
- *Option A (widen, GAP-3)* — "past dialogs" = this visitor's other conversations on this site,
  regardless of channel identity. Delivers the mockup for the common case. Cost: **M** + an
  authorization-boundary change (ADR + `personal-data.md`).
- *Option B (keep as-is)* — P1 shows only for channel-identified visitors; a widget visitor sees an
  empty/hidden row. Cost: **0**, but the mockup element is dead for most conversations.
- *Recommendation to weigh*: A, since the mockup shows the row unconditionally — but it is a real
  privacy-surface change and must be an explicit author decision.

**Q6 — Past dialogs: read-only or openable-to-act?** The console opens them strictly read-only. Cost:
read-only reuses the renderer for free; making them actionable is a larger, separate feature. Default:
read-only.

**Q7 — Per-element permission gating on mobile.** Confirm the sheet mirrors the console's
hide-not-disable per permission (`conversation:read` to see the sheet at all; `:tag`, `:note_write`,
`:close`, `:block`/`:mark_spam`, `:attachment_upload_grant`, `:send` per action). Any element the
author wants shown-but-disabled instead? Default: hide, matching the console and `navigation.md`.

**Q8 — Notes/past-dialogs counts: exact vs approximate.** Notes count = list length needs a list read;
if the author wants the count on the row *before* opening, either fetch the list on sheet-open (fine
for small N) or add a count to the `visitor-summary` endpoint. Cost: fetching on open is free-ish;
a count field is a few more columns on one query. Default: fetch notes list on open (N is tiny).

---

## 6. Proposed implementation-ticket breakdown (`26-112`…)

Each is one promise that lands green (rule 15). Backend-gap tickets (§2) come first because Android
tickets depend on their contracts. **Not filed here — proposed for the author to approve.** Numbers are
provisional. Repo tags: **[chat]** = ago-chat, **[console]** = ago-console, **[android]** = ago-android.

**Backend / contract (only the true gaps):**

- **26-112 [chat] — `GET /conversations/{id}/visitor-summary` returning `visitorFirstSeenAt` +
  `conversationCount`.** Closes GAP-1 + GAP-2. New Dapper read + handler (gated `conversation:read` +
  per-conversation check) + `Ago.Chat.Api` endpoint + `Ago.Chat.Contracts` DTO. No migration.
  *Depends on: none. Blocks: 26-118.* (Skip only if Q3 picks Option B, which folds into 26-116's
  DTO instead.)
- **26-113 [chat] — widen visitor "past dialogs" to per-visitor scope (GAP-3).** Replace the
  channel-identity gate with per-visitor scoping; update `personal-data.md`; add an ADR for the
  authorization-boundary change; access-record parity; tests. *Depends on: none. Blocks: 26-119.*
  **Gated on Q5 = widen.** If Q5 = keep, this ticket does not exist and 26-119 targets channel-only.
- **26-114 [chat + console] — allow `Name` assessment (GAP-4 / Q1 Option B only).** Domain rule +
  handler + console `assessable()` + tests + doc line. *Depends on: none. Blocks: nothing (Android
  reads it through 26-115).* **Only if Q1 = Option B.**

**Android — foundations (thin, reusable clients; one promise each):**

- **26-115 [android] — chat contact-details client + reveal.** `ContactDetailsApi` port +
  `KtorContactDetailsApi`: list + reveal (edit/assessment only if Q1=B). Reuses the 26-53 reveal-result
  shape. Green = list renders + reveal replaces the masked row (unit-tested adapter). *Depends on:
  none.*
- **26-116 [android] — conversation-tags client.** list-applied + list-site-vocab + apply + remove.
  *Depends on: none.*
- **26-117 [android] — conversation-notes client.** list + add. *Depends on: none.*
- **26-118 [android] — visitor-summary client** (H4/H5). *Depends on: 26-112 (or, if Q3=B, on the
  grown queue DTO — then this ticket is absorbed into the queue mapping).* 
- **26-119 [android] — visitor past-dialogs client** (list + open-one, read-only). *Depends on:
  26-113 if Q5=widen, else none.*
- **26-120 [android] — conversation write actions: close, restrict, attachment-grant toggle.** Adds
  `close` / `block-visitor` (+ `close-as-spam` if Q2=B) / `grant`+`revoke` to the Android conversations
  port, each `Succeeded/Refused/Failed`. *Depends on: none.* (Could split close vs restrict vs toggle
  if any one grows; keep together only while each stays a small write.)
- **26-121 [android] — `Permission` constants + localized emoji-name dictionary.** The gating strings
  and the H2 fallback dictionary. Small; can land early. *Depends on: none.*

**Android — the sheet itself (composes the above):**

- **26-122 [android] — contact-detail bottom sheet: shell + header + open-from-thread.** The
  `ModalBottomSheet`, its open affordance on `ThreadScreen`, header H1–H3 from the in-hand
  `ConversationSummary`, and H4/H5 from 26-118. Green = sheet opens over the thread and shows the
  header. *Depends on: 26-118, 26-121.*
- **26-123 [android] — sheet: КОНТАКТНЫЕ ДАННЫЕ section** (fields, masked + Показать, name pill per
  Q1, caption). *Depends on: 26-115, 26-122.*
- **26-124 [android] — sheet: tags section** (chips + «+ метка»). *Depends on: 26-116, 26-122.*
- **26-125 [android] — sheet: «Заметки команды» row + notes sub-screen.** *Depends on: 26-117,
  26-122.*
- **26-126 [android] — sheet: «Прошлые диалоги» row + read-only history open.** *Depends on: 26-119,
  26-122.*
- **26-127 [android] — sheet: «Приём файлов от посетителя» toggle.** *Depends on: 26-120, 26-122.*
- **26-128 [android] — sheet: «Закрыть диалог» + «Ограничить» actions** (confirm dialogs, per Q2).
  *Depends on: 26-120, 26-122.*

*Ordering rationale:* backend gaps (26-112/113/114) unblock the clients; clients (115–121) are
independent and parallelisable across lanes (distinct files → non-interfering, rule 13); the sheet
sections (122–128) each land green on top of their one client. 26-122 is the join point every section
depends on. The migration lane is not needed — none of the gaps require a schema migration (all
columns exist).

---

## Appendix — permission map (for gating, verbatim from ago-chat/console)

| Action | Permission |
|---|---|
| See the sheet / read contact-details / reveal / read tags / read notes / read history | `conversation:read` |
| Edit contact detail / set assessment / request channel link | `conversation:send` |
| Apply/remove tag | `conversation:tag` |
| Add note | `conversation:note_write` |
| Close conversation | `conversation:close` |
| Restrict: block visitor | `conversation:block` |
| Restrict: close as spam | `conversation:mark_spam` |
| Attachment-upload grant toggle | `conversation:attachment_upload_grant` |

All hide-not-disable; the server's `IPermissionChecker` is the real boundary.

---

## Author decisions (2026-09-25) — these supersede the open questions above

1. **No "Недействительно" / name-assessment.** The name is always trusted and shown as written — we
   cannot and need not verify it; if a person asks to be addressed a certain way we just record and use
   it. **GAP-4 (Name assessment) is dropped entirely.** The КОНТАКТНЫЕ ДАННЫЕ «Имя» row is plain text,
   no invalid state, no label.
2. **«Ограничить» is one reversible action.** A block is a *status*, not an irreversible act: the panel
   shows «Ограничить»; a blocked visitor shows «Снять ограничение» to reverse it. Reuse the console's
   existing reversible restriction mechanism (`visitorRestrictionsApi` / `RestrictedVisitorsPage`). The
   un-block path is in scope. No second destructive verb.
3. **Widen «Прошлые диалоги» to all visitors** (including widget-only, no channel identity): the row lists
   *this visitor's other conversations on this site*, so it is never dead. Needs the ADR + `personal-data.md`
   update (privacy-boundary change).
4. **Header via a new `visitor-summary` endpoint** (first-visit date + dialog count). Confirmed.
5. **«N диалогов» = count of this visitor's distinct conversations on this site, including the current
   one**, same widened scope as #3 — the header N and the «Прошлые диалоги» list always agree (current one
   marked). Past dialogs are **read-only** (view transcript, no takeover). Count **on panel open** (few per
   visitor — cheap; no dedicated count fields).

Implementation is filed as `26-114` (chat: visitor conversation history + summary + ADR), `26-115`
(android: contact-panel data clients), `26-116` (android: Permission constants + emoji-name fallback), and
further tickets as lanes free (bottom-sheet shell, per-section UI, write actions incl. reversible block).
