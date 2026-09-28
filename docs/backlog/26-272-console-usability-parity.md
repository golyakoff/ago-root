# 26-272 · [design] Console usability parity with the Android app — audit + prioritized plan

- **Stage**: 26. Kind: research + design proposal + recommended ticket breakdown (this file is the
  design; the slices in §6 are to be filed as their own numbered items). Author need stated 2026-09-28:
  "the web console (`ago-console`, office.agochat.ru) has fallen behind the app in usability."
- **Status**: proposed — not yet sliced into GitHub issues. Research deliverable for the managing
  session to slice from.
- **Repos touched by the proposed slices**: `ago-console` (the surface under audit), `ago-android`
  (the UX leader, referenced), `ago-calendar` (one small read-model addition, deferred). No platform
  change.
- **Scope boundary**: `26-268` (operator manual booking entry) and `26-269` (Записи ▸ Клиенты
  redesign) already carry **console mirror slices** (`26-268` §8 slice #4, `26-269` §8 slices #3 & #4).
  This document does **not** re-propose those; it references them and covers only gaps **beyond** them.

---

## 0. The honest headline (stated first, because it reframes the request)

The audit does **not** support "the console has fallen behind broadly." Measured screen by screen
against the app, the console is **at parity or ahead** on the operator's highest-traffic surface — the
live dialog workspace — and has real, comparably-sized screens for every settings/config area the app
has. The genuine residual gap is **narrow and concentrated in the Записи (bookings) operational
screens** and in **one missing cross-navigation edge** (an open dialog → that visitor's bookings /
client record). Two of the three worst spots the author is reacting to are **already scheduled**
(`26-268`, `26-269`).

Calling this out is the point of the audit, not a hedge: padding a plan with cosmetic "parity" tickets
that import mobile idioms (bottom sheets, segmented tabs, swipe) onto a desktop surface where they are
not improvements would spend the author's scarce review capacity
(`feedback_acceptance_throughput_is_the_bottleneck`) on motion without payoff. The plan below is
deliberately short.

---

## 1. Surface-by-surface comparison (grounded in files)

Legend: **App ahead** = the app does this measurably better and the console should follow; **Parity /
console ahead** = no action; **Planned** = already covered by `26-268`/`26-269`.

| Operator task | Console | Android | Verdict |
|---|---|---|---|
| **Live dialog** (thread, send, attachments, history paging, presence) | `src/pages/ConversationPage.tsx` (933 lines) + `src/workspace/*` | `thread/ThreadScreen.kt` (1130) | **Parity / console ahead** — see §2 |
| **Dialog queue / rail** (assigned vs waiting, take, tag filter) | `src/workspace/ConversationList.tsx`, `TagFilter.tsx` | `conversations/ConversationListScreen.kt` (1814) | **Parity** — see §2 |
| **Visitor / contact panel** (notes, tags, outcome, channels, history) | `VisitorPanel.tsx`, `ConversationNotesPanel.tsx`, `ConversationTagsPanel.tsx`, `ConversationOutcomePanel.tsx`, `ChannelIdentitiesPanel.tsx`, `VisitorHistoryPanel.tsx` | `thread/contactpanel/**` | **Parity** — but missing one edge, see §3.3 |
| **Bookings ▸ Ожидают** (pending veto queue) | `src/pages/CalendarQueuePage.tsx` | `bookings/PendingBookingsScreen.kt` (`26-163`) | **App ahead** — see §3.1 |
| **Bookings ▸ Утверждены** (confirmed) | `src/pages/CalendarBookingsPage.tsx` | `bookings/ConfirmedBookingsScreen.kt` (`26-117`) | **App ahead** (drill-in) — see §3.2 |
| **Bookings ▸ manual entry** | (none yet) | (none yet) | **Planned** — `26-268` (console mirror = its slice #4) |
| **Bookings ▸ Клиенты** (contacts) | `src/pages/CalendarContactsPage.tsx` | `bookings/ContactsScreen.kt` | **Planned** — `26-269` (console mirror = its slices #3, #4) |
| **Readiness hub** ("can a client book now") | `src/calendar/BookingReadiness.tsx` (used from `CalendarSetupPage`, `CalendarWorkersPage`) | `bookings/ReadinessBody.kt` (`26-164`) | **Parity** — both exist |
| **Services / Workers / Hours dictionaries** | `CalendarServicesPage`, `CalendarWorkersPage`, `CalendarAvailabilityPage`, `CalendarWorkerSlotsPage`, `CalendarWorkerRecutPage` | `bookings/ServicesScreen.kt`, `MastersBody.kt`, `schedule/WorkingHoursScreen.kt`, `WorkerSlotsScreen.kt`, `WorkerRecutScreen.kt` | **Parity** |
| **Team** (roster, invite, roles) | `OperatorsTeamPage.tsx` (945) | `team/PeopleScreen.kt` (955), `InviteColleagueSheet.kt` | **Parity** |
| **Team chat** | `TeamChatPage.tsx` | `team/TeamChatScreen.kt` | **Parity** |
| **Channels** (widget install, TG/MAX/VK/email) | `InstallSnippetPage`, `WidgetConfigPage`, `TelegramChannelPage`, `MaxChannelPage`, `VkChannelPage`, `EmailChannelPage` | `channels/ChannelConnectScreen.kt`, `InstallWidgetScreen.kt`, `WidgetConfigRoute.kt` | **Parity** |
| **Branding / appearance** | `AppearanceSettingsPage.tsx`, `WidgetConfigPage.tsx` | `channels/BrandingScreen.kt`, `WidgetAppearanceEditor.kt` | **Parity** |
| **Canned responses** | `CannedResponsesPage.tsx` (222) | `automation/CannedResponsesScreen.kt` (463) | **Parity** — neither has search; the app's extra lines are the edit sheet, not a feature the console lacks |
| **Tags** | `TagsPage.tsx` (261) | `automation/TagsScreen.kt` (394) | **Parity** |
| **Analytics** (me / site / conversion / tags / booking-flow / phone-reveals) | `OperatorAnalyticsPage`, `SiteAnalyticsPage`(via `AdminConversationsPage`?), `ConversionReportPage`, `TagBreakdownReportPage`, `BookingFlowConversionPage`, `CalendarPhoneRevealsPage` | `analytics/**` (overflow-menu hub) | **Parity** — same reports both sides |
| **Offline auto-reply / FAQ / AI draft** | `OfflineAutoReplyPage`, `FaqModulePage`, `AiReplyDraftPage`, `AiAddOnPage` | `automation/OfflineAutoReplyScreen.kt`, `faq/ModulesFaqScreen.kt`, `automation/AiReplyDraftScreen.kt` | **Parity** |

### 1.1 Navigation model — considered and deliberately NOT changed

The app collapses Записи into a **three-segment control** (Ожидают / Утверждены / Клиенты) plus a `⋮`
config menu (Готовность / Календари / Мастера / Услуги / Часы) — `bookings/BookingsTab.kt`,
`visibleBookingsSegments` / `visibleBookingsConfigMenuEntries`. It did this because **five segments
wrap on a phone** (`26-103`). The console's equivalent is a **flat left-rail section** with up to seven
calendar entries (`src/shell/consoleNav.ts`, `buildCalendarItems`).

**This is not a gap to close.** The segmented+`⋮` design is a workaround for a constraint the desktop
rail does not have; on a wide screen a flat rail puts every screen one click away and is the better
idiom. Importing the mobile IA would be a regression. No ticket.

---

## 2. Why the dialog workspace is NOT a gap (evidence)

The instinct behind the request is that the app "feels" better, so the console must be behind
everywhere. On the daily-driver surface it is not:

- `ConversationPage.tsx` already has: deferred SignalR join with reconnect-safe re-join guard, keyset
  history paging, `?at=`-driven search-hit location (`18-01`), live delivery acks (`25-119`),
  presence polling, per-message attachment thumbnails with a safe cross-origin download rule (`5-08`),
  AI "suggest a reply" (`19-01`), debounced mark-read that respects tab visibility (`5-15`), and a
  graceful closed/join-error composer suppression (`11-09`/`18-01`).
- The rail (`ConversationList.tsx`) already splits **assigned vs waiting**, makes a waiting row a real
  one-click take (`23-04`), leads every row with elapsed time (`waiting 14m`, not a clock), and states
  the freshness difference between the live and polled halves.
- The visitor panel already has notes, tags, outcome capture, channel identities, and returning-visitor
  history (`src/workspace/*Panel.tsx`), plus keyboard shortcuts (`useShortcuts.ts`, `ShortcutsDialog`)
  the app has no equivalent of.

The one thing the app's list has that the console rail does not is an **in-rail text filter / segment
chips** (`ConversationListScreen.kt` imports `FilterChip`, `SegmentedButton`). The console instead has
a **separate** admin-only `/conversations/search` page (`SearchConversationsPage.tsx`) and the
`TagFilter`. This is a plausible small enhancement (an inline name/text filter over the loaded
assigned+waiting lists, client-side, mirroring `26-269`'s decision that client-side filtering is the
honest v1 for tenant sizes this product targets) — but it is a **minor** add, listed as **optional
T5** below, not a headline gap.

---

## 3. The real gaps (beyond 26-268 / 26-269)

### 3.1 Pending queue shows a raw calendar-id hex column (the exact "engineering view" the app removed)

`CalendarQueuePage.tsx:245` renders a whole column as
`<span className="ago-mono">{row.calendarId.slice(0, 8)}</span>` — an eight-hex-char calendar id, per
row, with a truncated-id header. This is the identical "raw engineering view" (`Календарь 01a084eb`)
the app's `26-163` deliberately deleted from its pending screen because "the wire had carried every
name since `26-50`" and the hex told an operator nothing actionable.

Unlike the app's other `26-163` fixes, the console does **not** have the raw-GUID-as-identity problem
elsewhere: `renderPersonName` (`src/calendar/calendarFormat.tsx:71`) already degrades to a localized
"name not recorded / unavailable" label and **never** prints a person GUID. So the calendar-id column
is the one genuinely raw artifact left on this screen.

**Fix**: drop the column (the calendar is chosen elsewhere; the tenant's own queue spans all calendars
by design — `CalendarQueuePage`'s own "one queue" doc comment). If multi-calendar disambiguation is
ever wanted, it needs a calendar **name** on `PendingBookingResponse` (the wire carries only the id
today) — that is a calendar read-model change with a number of its own, not part of this cleanup.
**Frontend-only, tiny, high signal-to-effort.** → **T1**

### 3.2 No booking-detail drill-in on the two operational booking screens

The app gives each pending and confirmed booking a **tap-to-open detail** (`ModalBottomSheet`,
`26-117`/`26-135`/`26-163`) consolidating the full fact set — service, worker, phone, date/time,
duration, and (confirmed only) «Источник» → dialog and «Подтверждён по SMS» — with the row's actions.
The console screens are flat `Table`s: `CalendarQueuePage.tsx` columns end at inline reject/cancel
buttons; `CalendarBookingsPage.tsx` shows a table with a "go to dialog" `Link`
(`CalendarBookingsPage.tsx:332`) and reschedule, and no consolidated detail.

On desktop a **modal is the wrong idiom** — the right one is a **row-expand or a right-side detail
panel** (the same pattern the workspace already uses for the visitor panel). The confirmed screen's
detail is a pure frontend change: every fact the app's sheet shows (`ConfirmedBooking` carries
`originConversationId`, times, service, worker, masked phone) is already on the wire. → **T2**

The **pending** screen's detail would want the same «Источник» / SMS-confirmed rows, but
`PendingBookingResponse` carries **neither** `originConversationId` (added to the confirmed model only,
`26-121`) nor an SMS-confirmed flag — exactly the gap `PendingBookingsScreen.kt`'s own doc comment
names as "an additive calendar change with a number of its own." That read-model addition is **deferred
(T6)**, not v1: a pending row is transient (it self-confirms within hours), so a rich detail on it is
low payoff.

### 3.3 No path from an open dialog to that visitor's bookings / client record (the missing cross-nav edge)

`26-269` builds the **client → dialog** and **client → booking** edges (its client-detail hub, reached
from the Клиенты list, with per-person reads: calendar bookings by person = its slice #1, chat
conversations by person = its slice #2). The **reverse edge is still missing**: from an open
conversation, an operator cannot see "does this visitor have an upcoming booking?" or jump to the
client hub. `VisitorPanel.tsx` / `VisitorHistoryPanel.tsx` surface past **conversations** only — a grep
for any booking/calendar reference in those files returns nothing.

For a **calendar** tenant this is the highest-payoff of the three gaps: an operator on a live chat with
"can you remind me my appointment time?" has to leave the dialog, go to Записи ▸ Клиенты, search, and
open the client — instead of seeing the upcoming booking right in the visitor panel. This is the
booking↔dialog↔client triangle's missing third side.

It **reuses `26-269`'s per-person bookings read** (that item's slice #1,
`GET /api/v1/console/contacts/{personId}/bookings`) — no new backend if `26-269` lands first — and
adds a compact "upcoming bookings + open client" affordance to the visitor panel, deep-linking the
`26-269` client-detail route. → **T3** (depends on `26-269`). Mirror on android's contact panel.

**Design decision to settle when built, not now** (teaching-mode: flag, don't decide silently): whether
the affordance links to the **full `26-269` client-detail route** or renders an inline mini-list in the
panel. Recommendation: link to the client-detail route — one hub, not two divergent booking views to
keep in sync (the same "one place makes the decision" discipline the nav and `renderPhone` reuse
already follow). But this is `26-269`-dependent, so it is the slice author's call at build time.

---

## 4. Considered and rejected (so the next reader does not re-litigate)

- **Mobile IA on desktop** (segmented Записи tab, `⋮` config menu, bottom sheets, swipe-to-act) —
  rejected, §1.1. Desktop constraints differ; these would regress.
- **Person-GUID identity fallback** — the app's `26-163`/`26-269` fix does not apply: the console
  already never prints a person GUID (`renderPersonName`, §3.1).
- **Booking detail as a modal** — rejected in favour of row-expand / side panel (§3.2); modals are the
  phone's answer to no screen space.
- **Server-side search anywhere** — same call `26-269` §9 made: client-side filtering is the honest v1
  at this product's tenant sizes (zero real tenants today). Any in-rail dialog filter (T5) is
  client-side too.
- **No-show / outcome capture on confirmed bookings** — a real gap, but **already owned**: `26-175`
  deferred the lifecycle actions and `26-268` §7 (slices O1–O5) is the outcome-capture design. Not
  re-proposed here; referenced.

---

## 5. Does any gap warrant its own design pass?

No. All three real gaps (§3) are small and either frontend-only (T1, T2) or a thin reuse of a read
another already-designed item builds (T3). None needs an ADR: no new permission, no new write
semantics, no cross-product coupling (T3 stays within the client-side display-merge `adr/0184`
decision 4 already prescribes, exactly as `26-269` does). This document is the design; §6 is directly
sliceable.

---

## 6. Recommended ticket breakdown (one ticket = one promise that lands green — rule 15)

Ordered by user-visible payoff ÷ effort.

1. **T1 · [ago-console] Drop the raw calendar-id column from the pending queue.**
   `CalendarQueuePage.tsx` — remove the `calendar` column (`:238–246`) and its
   `calendarQueueColumnCalendar` string usage; adjust the table + its test/fixture; i18n cleanup for
   the now-unused string. One promise: the pending queue shows no raw ids. **Frontend-only, no
   backend.** `typecheck && lint && test && ux-gate` green
   (`feedback_ago_console_full_command_set_includes_ux_gate`). *(No android mirror — `26-163` already
   did this there.)*

2. **T2 · [ago-console] Confirmed-bookings row detail (expand or right-side panel).**
   `CalendarBookingsPage.tsx` — a row-expand / side detail showing the full booking (service, worker,
   phone with the existing `renderPhone` reveal, date/time, duration, «Источник» → dialog link,
   SMS-confirmed status) consuming the data already on the `ConfirmedBooking` wire; reschedule stays
   reachable from it. One promise: opening a confirmed booking shows its full detail on one surface.
   **Frontend-only** (wire unchanged). i18n both languages, page test + fixture, ux-gate.

3. **T3 · [ago-console + ago-android] Open dialog → visitor's bookings + client hub.**
   Add to the visitor panel (`VisitorPanel.tsx`; android `thread/contactpanel/**`) a compact "upcoming
   bookings for this visitor + open client" affordance, consuming `26-269`'s per-person bookings read
   (its slice #1) and deep-linking the `26-269` client-detail route. One promise: from an open
   conversation the operator can see this visitor's upcoming bookings and reach their client record.
   **No new backend if `26-269` slice #1 lands first** (hard dependency). Cross-repo, so one worker owns
   both surfaces (`feedback_one_worker_per_cross_repo_task`). i18n / string resources both languages;
   tests + ux-gate (console) and VM tests (android).

**Deferred / optional (file when justified, not v1):**

- **T5 · [ago-console] In-rail dialog filter.** A client-side name/text filter over the loaded
  assigned+waiting rail (`ConversationList.tsx`), mirroring the app's `FilterChip`/segment affordance
  and `26-269`'s client-side-filter posture. Minor; file if the author wants it. Frontend-only.
- **T6 · [ago-calendar + ago-console] Pending read-model gains `originConversationId` (+ SMS-confirmed
  flag), then a pending-queue detail with «Источник».** The "additive calendar change with a number of
  its own" `PendingBookingsScreen.kt` names. Low payoff (pending rows are transient); file only if
  wanted. Cross-repo, migration-free (read-model/contract only), one worker.

**Order**: T1 (tiny, immediate) → T2 (frontend, no deps) in parallel → T3 after `26-269` slice #1
lands. T5/T6 only on demand.

---

## 7. Deviations from the request's framing (with reasoning)

- **The gap is narrower than "fallen behind broadly."** The audit found parity or console-ahead on the
  dialog workspace and every settings area; the real gaps are three, concentrated in Записи and one
  cross-nav edge (§0). Reporting the true, small scope is more useful than a padded parity sweep, given
  the author's review capacity is the constraint.
- **Two of the three worst spots are already scheduled** (`26-268`, `26-269`); this file references
  rather than re-files them (`feedback_never_close_an_item_a_pr_only_files` discipline — do not create
  overlapping tickets).
- **No mobile-idiom ports.** Segmented tabs, bottom sheets, and swipe are phone answers to phone
  constraints; the desktop equivalents (flat rail, row-expand, side panel) are the right targets (§1.1,
  §3.2).
- **No new ADR / no backend for v1** (T1–T2); T3 reuses `26-269`'s read within the `adr/0184`
  display-merge boundary.
