# 26-16 · The bottom navigation and the back-button contract

- **Stage**: 26
- **Status**: done — `ago-android#22`; remainder carried out to `26-22`
- **Found**: 2026-09-21. `navigation.md` §"What the back button does" opens with the reason this is a
  real item rather than a detail of some other one: "Android's system back is a real contract and the
  console has no equivalent of it, so it is stated once here." Six clauses, none of which any screen
  item would own.
- **Verified**: 2026-09-21 — the hide-when-empty rule is the console's own and is documented in
  `ago-console/src/shell/consoleNav.ts:57-67`: `buildSection` returns `null` rather than an empty
  section and the caller filters those out, which is what makes an ordinary operator's rail four
  sections rather than seven collapsed ones. That file also carries `permissionsKnown` as a distinct
  state from "has no permission" — worth porting, since drawing a four-item bar because permissions
  have not loaded yet is a different bug from drawing one because the operator lacks the grant.
- **Depends on**: `26-14` (a real destination to navigate to), `26-12` (the session the permission set
  comes from).

## What this item is

The app's shell: five destinations, drawn according to what this operator actually holds, and a back
button that behaves the way `navigation.md` specifies. One promise: **the app navigates correctly.**

## Scope

- **Five destinations in `navigation.md`'s own order — Диалоги, Записи, Команда, Аналитика, Ещё** —
  ordered by how often a shift touches each, not by the console rail's order. An earlier draft had
  Команда and Аналитика the other way round and the author corrected it; the corrected order is what
  every mockup frame and `architecture.md` now state.
- **A destination with nothing inside it is not drawn.** The identical rule `buildSection` applies: an
  ordinary operator with no calendar grant sees **four** destinations, not five greyed ones; an
  administrator sees five. The floor is four, because Команда, Аналитика and Ещё each always carry at
  least one item, so the bar never degrades into something Material has no shape for.
- **The permission vocabulary in `:core:domain`** — arriving now because this is its first consumer,
  which is the same rule `0-01` applied to the platform's ports — and the operator's own permission
  set read once per session, with **"not loaded yet" distinguished from "not held"**.
- **Every gate is the same gate the console applies, for the same stated reason**: hiding a control is
  UX, and the server's own `IPermissionChecker` is what actually refuses (`authorization.md`,
  `scope-inventory.md`'s own gate column). The app invents no permission of its own.
- **Ещё as a list-of-lists** — the three folded sections as headers, their items as rows, no nesting
  beyond that. Rows exist only for screens that exist; a row pointing at nothing is the same
  hide-when-absent rule, not a placeholder to fill in later.
- **The back-button contract, all six clauses** (`navigation.md`):
  - back from a thread returns to the list, keeping scroll position and filters;
  - back from any Ещё screen returns to the Ещё list, not to the previous bottom-bar destination;
  - back on a bottom-bar destination other than Диалоги returns to Диалоги; back on Диалоги exits;
  - back inside a multi-step flow returns to the previous step (the re-cut is the case this was
    written for; it is not in this wave, but the rule is implemented here);
  - sheets, filter sheets and confirmation dialogs are dismissed by back before the screen under them;
  - **back never discards a composer draft silently.**

## Out of scope

- **The tablet navigation rail and `ListDetailPaneScaffold`** — `plan.md`: phone first, tablet last,
  and no phase is gated on it.
- Any Записи, Команда or Аналитика screen. The destinations exist and are empty-but-honest; their
  contents are later waves.
- Deep links. The two push ones arrive with `26-18`; App Links for invites and policies are their own
  later item.
- The Settings screen itself (`26-17`) — this item puts the row in Ещё.

## Done when

- [~] An operator without a calendar grant sees four destinations; one with it sees five — both
      against real identities on a real phone, not fixtures. **Carried to `26-22`** - the one real
      device available this session was never signed in against an identity confirmed to lack the
      calendar grant, so only one side of this pair has any chance of being observed by construction.
- [x] Permissions still loading does not render a wrong bar that then changes under the operator —
      say what it renders instead. Renders a full-screen loading state
      (`AppShellScreen`'s own `when` on `OperatorPermissions.Unknown`) and never calls
      `visibleBottomDestinations` at all until the real answer is in - confirmed by reading
      `AppShellScreen.kt` directly, and by `AppShellViewModelTest`.
- [x] **Every clause of the back contract has a Compose UI test**, written here and run in CI by
      `26-20`. Ten new instrumented tests, one or more per clause, confirmed independently by running
      them myself - not merely trusting the implementing worker's own report - on a real physical
      device (`2407FPN8EG`), 0 failures. Wiring them into CI is `26-20`'s own job, unchanged.
- [~] Rotating the device and returning from the background preserves the selected destination and
      each destination's own back stack. **Carried to `26-22`** - no automated test exercises a real
      `Activity` recreation of the shell itself (as opposed to `26-14`'s own conversation-list
      rotation proof, which *was* observed live this session, separately); architecturally covered by
      `NavController`'s own saved state and `rememberSaveable`, the identical shape `26-14`'s
      equivalent box already relied on, but not yet confirmed on-device for this item's own shell.
- [x] `./gradlew ktlintCheck lint test` green; counts reported. 149 tests (44 `:core:domain`, 64
      `:core:network`, 41 `:app`), 0 failures; ktlint clean. Plus 20 instrumented Compose UI tests (10
      pre-existing, 10 new), 0 failures, run on a real device.

## Outcome

Landed as `ago-android#22`. Five bottom-bar destinations in `navigation.md`'s own corrected order,
computed by a pure `:core:domain` function (`visibleBottomDestinations`) over a new three-state
`OperatorPermissions` (`Unknown`/`Known`) so "not loaded yet" and "not held" never collapse into one
answer - the caller renders a loading screen for `Unknown` rather than a bar that could later change
under the operator. Navigation Compose (arriving with its first real consumer, `libs.versions.toml`'s
own remark) replaces `26-15`'s hand-rolled two-destination switch; the ordinary bottom-navigation
recipe (`popUpTo(start){saveState=true}` + `launchSingleTop` + `restoreState`, with Диалоги as the
start destination) gives back-contract clause 3 for free, with no custom `BackHandler` needed for it
at all - confirmed by reading `AppShellScreen.kt`'s own reasoning and independently re-derived rather
than taken on faith. Clauses 1 and 6 are `26-15`'s own proven mechanism, relocated unchanged into its
real home (`ConversationsTabHost`); clause 2 is `MoreScreen`'s own hand-rolled `openRowId` state with
a conditionally-enabled `BackHandler`; clause 4 is a new, reusable `StepFlowState`/`StepFlowBackHandler`
primitive built ahead of the first real multi-step flow that will need it; clause 5 is proven against
Material3's own `ModalBottomSheet` dismiss-consumes-back behaviour, honestly since no real sheet exists
in this app yet. Permission names (`calendar:configure`, the three `booking:*` actions, `customer:read`,
`site:manage_operators`, `site:configure`) are copied verbatim from the real backend vocabulary and
`ago-console/src/shell/consoleNav.ts`'s own gate list, cross-checked directly against both rather than
trusted from the item's own brief. Ещё is a list-of-lists porting the console's own
`buildSection`-returns-null-then-filter shape; every folded section is honestly empty this wave (no
Каналы/Автоматизация/Администрирование screen exists yet) except the Settings row, drawn as a stated
placeholder pending `26-17`.

**A real bug found and fixed during the implementing worker's own self-review**: an early version of
`BackContractDialogsTabTest`'s clause-6 test crashed its own test database
(`IllegalStateException: ... connection pool has been closed`) because a fake-backed `ThreadViewModel`
built directly (with no `hiltViewModel()` lifecycle owner) never had its `viewModelScope` cancelled,
so an earlier open's in-flight `flushDraft()` write raced the test's own `tearDown()`. Fixed with a
`rememberDisposableThreadViewModel` wrapper that cancels the scope on dispose - confirmed in place by
reading the test file directly.

**Verified independently, beyond the implementing worker's own report**: read every load-bearing
source file directly (`OperatorPermissions.kt`, `Permission.kt`, `BottomDestination.kt`,
`AppShellScreen.kt`, `MoreScreen.kt`, `StepFlow.kt`, `KtorOperatorPermissionsApi.kt`, and the
back-contract test suite); cross-checked the permission vocabulary against the real
`ago-console/src/shell/consoleNav.ts` gate names myself (matches exactly); confirmed
`KtorOperatorPermissionsApi` calls the real, existing `GET /api/v1/operators/me` endpoint, not an
invented one; re-ran the full unit-test suite myself (149 tests, matching the worker's own claimed
per-module counts to the exact number); and - beyond what the worker's own report could do from a
worktree with no device attached - **ran all 20 instrumented Compose UI tests myself, live, on a real
physical phone**, the same device this session's own `25-213`/`26-22` real-device proof used, 0
failures.

**Two boxes carried to `26-22`**: the four-vs-five-destination proof against a real identity known to
lack the calendar grant, and an on-device rotation/backgrounding confirmation of the shell itself
(distinct from `26-14`'s own conversation-list rotation proof, which *was* observed live this
session).
