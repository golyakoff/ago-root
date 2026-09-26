# 26-156 · [android] Contact-detail EDIT + assessment (Phone/Email) — console parity — scoping

- **Stage**: 26 (Android app). **Kind**: design/scoping; no production code, no tickets filed here.
- **Item**: `ago-root#1659` (placeholder, no backlog file). Named out-of-scope in
  `26-111-contact-panel-slices.md` §"Deferred placeholders"; `26-115` shipped list+reveal only and its
  `ContactDetailsApi` doc comment records that edit/assessment "exist on the server but are out of scope
  here … no ticket has asked for edit yet". This is that ticket.
- **Premise check (bg-worker-brief §0.6)**: backend complete, console complete, **Android has neither the
  client methods nor the UI**. No backend change, no migration.

## 1. Where the data lives now (post-ADR-0184) — designed against the right store

The rows the thread panel's «Контактные данные» section shows are **chat's `VisitorContactDetail`s**
(`Name`/`Phone`/`Email`) on chat's Person (`Visitor`) — `ago-chat`
`GET /api/v1/conversations/{id}/contact-details`. ADR-0184 decision 1 makes chat the owner of "contact
channels"; editing or assessing one of these rows therefore edits **the source of truth**, which is exactly
what the console's `ContactDetailsPanel` does. This item is designed against that store.

Two things it is deliberately **not** about, so nobody unifies them later:

- **The calendar `PersonRecord.Phone` (author decision O1)** — the number a person *last booked with*,
  kept only because the verified-phone gate and the per-phone rate limit read it in-transaction (rule 8).
  It changes only through `PersonRecord.ChangePhone` on a later booking; there is **no API to edit it** and
  there must not be one (its `PhoneVerifiedAt` is a statement about *that* number). The dropped `customers`
  table is gone; nothing here targets it.
- **The calendar «Прозвонен» fact** (`PersonRecord.PhoneConfirmedByOperatorAt`,
  `POST /contacts/{personId}/confirm-phone`) is a *different* assertion from chat's `assessment =
  Confirmed`, kept apart on purpose (`23-12`). Verified: **no client offers that action anywhere** — the
  console `CalendarContactsPage` and the Android Клиенты card both render it read-only. Out of scope; see Q5.

## 2. What already exists (verified against `origin/main`, 2026-09-26)

**Backend — `ago-chat` (`8530e22`), `ContactDetailEndpoints.cs`, operator-only:**

- `PATCH /api/v1/conversations/{id}/contact-details/{detailId}` `{value}` →
  `EditVisitorContactDetailHandler`, gated **`conversation:send`**; wrong-visitor reads as
  `VisitorContactDetail.NotFound`; empty/oversized → 400 `VisitorContactDetail.Invalid` (`detail` = the
  domain sentence); **`EditValue` resets `Assessment` to `Unset`** and never touches `Source`/
  `RecordedByOperatorId`; response = the full row, `masked: false`.
- `PATCH …/{detailId}/assessment` `{assessment: "Confirmed"|"Invalid"}` →
  `SetVisitorContactDetailAssessmentHandler`, gated `conversation:send`; `Unset` refused
  (`VisitorContactDetail.InvalidAssessment`); a `Name` row refused 400
  `VisitorContactDetail.AssessmentNotApplicable`; Confirmed ↔ Invalid may be flipped freely; **no path back
  to Unset** (the console has none either).
- `ContactDetailDto` carries `assessment` (`"Unset"`/`"Confirmed"`/`"Invalid"`) on every read and write
  response — the Android wire DTO simply omits it today (`ignoreUnknownKeys`).

**Console — `ago-console` (`2315100`), `ContactDetailsPanel.tsx`:** «Изменить» only when `canEdit &&
!masked` ("cannot correct a value you cannot read"); inline edit (Phone rows through the 🇷🇺 +7 `PhoneInput`,
`25-186`); «Подтвердить» hidden when already Confirmed, «Отметить как недействительный» hidden when already
Invalid; badges «Подтверждено» (success) / «Недействительно» (danger); per-row in-flight; edit/assessment
hidden (not disabled) without `conversation:send`; `Name` rows edit-only, never assessable. Strings:
`ru.ts:743-752`.

**Android — `ago-android` (`89dcc2f`):** `ContactDetailsApi` (list + reveal), `ContactDetail(id, kind,
value, masked)`, `ContactDetailsSection` (label / value / «Показать», per-row reveal error line),
`ContactPanelViewModel.revealContactDetail` idiom (in-flight set, `Refused(detail)` verbatim, `Failed`
generic), `ContactDetailsSectionState.Loaded(details, revealingIds, revealErrors)`. `canTagConversation` is
the precedent for threading a permission boolean `AppShellScreen → ConversationsTabHost → ThreadScreen →
ContactDetailPanel`; `Permission.CONVERSATION_SEND` exists. **No phone-input component** exists in the app.
`26-111` author decision **Q1** stands: `Name` is plain display text — no assessment, no caption.

## 3. What the Android section does

**Gate.** `canSendConversation = permissions.holds(CONVERSATION_SEND)` threaded exactly like
`canTagConversation`; when false, **no** edit/assess affordance is drawn (hide, not disable — `26-111` Q7).
Reading and «Показать» are unchanged (`conversation:read`).

**Row (Phone/Email).** Label (labelMedium, onSurfaceVariant) → value line: value (bodyMedium) · **assessment
word** when set — «Подтверждено» (onSurfaceVariant, with `AgoIcons.Check`) / «Недействительно» (`error`
colour) — a word, never a colour alone · «Показать» when masked (unchanged) · a trailing **row `⋮`**
(`AgoIcons.MoreVertical`, `DropdownMenu`) holding: «Изменить» (only when `!masked`), «Подтвердить» (only when
`assessment != Confirmed`), «Отметить недействительным» (only when `assessment != Invalid`). A menu with no
applicable entry is not drawn. *Why a menu:* three inline `TextButton`s beside a phone number do not fit a
phone's row; the console's inline buttons are its desktop shape (Q1).

**Row (Name).** «Изменить» only (console parity — a name can be corrected; `26-111` Q1 forbids *assessing*
it, not editing it — confirm, Q6). No pill, no caption.

**Edit.** Tapping «Изменить» turns the value line into an `OutlinedTextField` prefilled with the current value
(Phone → `KeyboardType.Phone`, Email → `KeyboardType.Email`), with «Сохранить» (disabled while blank or
saving) and «Отмена» — form-over-row, the app's own one-card-two-modes idiom. On success the **server's row
replaces it in place** (which also drops any assessment word, since `EditValue` resets it — stated in the
Kdoc, not hidden). `Refused(detail)` → the server sentence under the row, draft kept; `Failed` → generic
«Не удалось сохранить изменение.» Only one row edits at a time (opening another closes the first, discarding
the draft — nothing was sent).

**Assessment.** Single tap, no dialog (reversible Confirmed↔Invalid; an operator's own call, not
destructive). Per-row in-flight set disables that row's menu; success replaces the row; `Refused(detail)`
verbatim / `Failed` generic «Не удалось обновить статус.» — the identical
`revealingIds`/`revealErrors` shape, generalised to `pendingIds`/`rowErrors`.

**Copy.** New resources in both languages: `contact_details_action_edit`, `_save`, `_saving`, `_cancel`
(reuse `action_cancel`), `_confirm`, `_mark_invalid`, `_assessment_confirmed`, `_assessment_invalid`,
`_edit_failed`, `_assessment_failed`, `_row_actions` (the `⋮` contentDescription). Russian mirrors `ru.ts`.

## 4. Backend change

**None required.** Two known, deliberately out-of-scope items, named so they are not rediscovered:
(1) the reveal `surface` is still hardcoded `ConsoleContactPanel` server-side (`26-115`'s recorded gap — an
`AndroidThread` surface needs a chat change no ticket has filed); (2) there is **no reversal to `Unset`** on
either client — an additive change (accept `Unset` in `SetVisitorContactDetailAssessmentHandler` + a console
«Снять отметку») is possible but is a product decision (Q4), not this item.

## 5. Product questions for the author

- **Q1 — Affordance shape.** Row `⋮` menu *(recommended for a phone row)* vs inline `TextButton`s (console
  shape) vs long-press context menu.
- **Q2 — Edit while masked.** Hidden until revealed (console rule) *(recommended)* — confirm.
- **Q3 — Phone editing input.** Plain field with the phone keyboard *(recommended now, zero new
  components)* vs porting the console's 🇷🇺 +7 `PhoneInput` (`25-186`) as a shared Android component — a
  separate small item if wanted, since the widget/console treatment exists for a reason (`+1…` escape hatch).
- **Q4 — Reversal to `Unset`.** Leave absent (parity; recommended) vs an additive chat + console + Android
  change.
- **Q5 — Calendar «Прозвонен» action.** Not this item; does the author want an Android (and console) affordance
  for `POST /contacts/{personId}/confirm-phone` on Клиенты as its own item? Today nobody can set it from any
  client.
- **Q6 — `Name` edit.** Editable like the console (recommended) vs display-only (a stricter reading of
  `26-111` Q1 "trust whatever the person entered").
- **Q7 — Assessment word style.** Word + glyph in neutral/`error` colours (the app's «Неактивен» rule) — or a
  chip/badge like the console's `Badge`?

## 6. Proposed implementation tickets (provisional — managing session assigns real numbers, ~26-171+)

One promise each (rule 15); repo tag **[android]**; no migration lane.

- **26-171 [android core] — contact-detail write client.** Add `assessment` to `ContactDetail` (raw wire
  string, `Unset` default) + `ContactDetailsApi.editContactDetail(conversationId, detailId, value)` and
  `setContactDetailAssessment(conversationId, detailId, assessment)` → one
  `ContactDetailWriteResult { Updated(contactDetail) | Refused(detail) | Failed(reason) }`; Ktor adapter;
  tests (success, 400 `detail` refusal, transport failure, `assessment` parsed on the list read).
  `core/**` only. *Depends on: none.*
- **26-172 [android app] — assessment on Phone/Email rows.** Assessment word + row `⋮` with
  Подтвердить/Отметить недействительным; `pendingIds`/`rowErrors` generalisation of the reveal transient
  state; VM `setAssessment`; `canSendConversation` threaded through the shell to the panel; strings;
  `ContactDetailsSectionTest` cases (word rendered, actions hidden without the permission, hidden when
  already in that state). *Depends on: 26-171. Serializes with any open `26-150…153` panel slice
  (shared `ContactDetailPanel.kt` / `ContactPanelUiState.kt` / VM / `strings.xml`).*
- **26-173 [android app] — inline edit.** «Изменить» in the row `⋮` (hidden while masked), form-over-row
  editor, VM `editContactDetail`, in-place replace incl. the reset assessment; strings; tests. *Depends on:
  26-172 (shares the menu + transient state). May be merged into 26-172 if the author prefers one PR — it is
  split here because "edit" and "assess" are two promises with two failure shapes, the same seam the
  server's two routes already cut.*

Closing `#1659`: umbrella, closed when 26-173 merges.
