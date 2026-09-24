# 26-70 · Аналитика has no overflow, and no «Аналитика сайта» behind it

- **Stage**: 26
- **Status**: done — merged as [ago-android#84](https://github.com/golyakoff/ago-android/pull/84). Real
  finding along the way: `BackContractBottomBarTest.clause3_backNeverWalksThroughPreviouslyVisitedTabs`
  clicks «Аналитика» and now composes real content through `hiltViewModel()` — `AppShellScreen`'s own
  comment claiming no test visits Аналитика's content is no longer true. Not fixed here (instrumented
  tests aren't in the verification command run, so a fix couldn't be proven safe); if it fails on a
  real device run, the fix is an `analyticsTab` slot mirroring `teamTab`, worth its own item.
- **Found**: 2026-09-23, reading `ago-console/src/pages/OperatorAnalyticsPage.tsx`,
  `ago-console/src/api/conversationsApi.ts` and `ago-console/src/realtime/protocol/types.ts` against
  `ago-android` `main` at `b099282`, with the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`)'s own `subgraph A["4 · Аналитика"]`.

## Found

`26-58` decided all five administrator reports port to Android, and that they arrive as four
destinations behind one overflow on Аналитика rather than as tabs or one screen with a picker. This
is the first of them — **and the overflow itself**, because the two are one promise. An overflow
that opens an empty menu is the exact inert-control shape `26-40` refused to add to the thread's own
app bar ("an overflow that opens an empty menu is the same 'inert control' shape `26-15` rejected",
`docs/backlog/26-40-*.md:118-120`), and `26-57` deliberately did not add one for the same reason
(`26-57`'s own Out of scope).

## What is actually true today, confirmed against real code

- **There is no overflow on Аналитика and no sub-screen under it.** `AppShellScreen.kt:285` wires
  the whole destination to one composable; `26-57` replaces that with «Мои показатели» and adds no
  app-bar action.
- **The app already has the exact overflow shape to copy**, once:
  `ConversationListScreen.kt:243-266` (`ConversationListOverflowMenu`) — `AgoIcons.MoreVertical`
  (`AgoIcons.kt:131`), a plain `remember` for `expanded` rather than `rememberSaveable`, and the
  menu closed *before* the callback runs. Its own doc comment states the rule this item inherits:
  the menu exists so the next screen-level action has somewhere to go, and it holds only items that
  have a screen.
- **The app already has the "one level deep, hand-rolled, `BackHandler`-owned" sub-navigation
  shape**: `MoreScreen.kt:64-69`'s `openRowId`, which `MoreScreen.kt`'s own doc comment ties to
  `navigation.md`'s back-contract clause 2. Аналитика's overflow destinations are the same shape —
  back from a report returns to Аналитика, not to the previous bottom-bar destination.
- **Gating is already available and already three-state.** `OperatorPermissions.holds(...)`
  (`core/domain/.../permissions/OperatorPermissions.kt`) answers `false` for `Unknown` on purpose;
  `AppShellScreen.kt:136,166,187` already carries `OperatorPermissions.Known` into the shell. The
  console's own gate for these four is `site:configure`, applied per nav entry at
  `ago-console/src/shell/consoleNav.ts:189-194`.
- **What `/analytics/site` actually is.** `App.tsx:370` → `OperatorAnalyticsPage`, reading
  `GET /api/v1/conversations/analytics` (`conversationsApi.ts:441`) with **both bounds optional**
  (`conversationsApi.ts:423-433`; the server applies its own thirty-day default). The response
  (`types.ts:341`) is `from`/`to`, `overall`, `previousFrom`/`previousTo`/`previousOverall`, and
  **four independent breakdown arrays**: `byChannel`, `byOperator`, `byReferrer`, `byCampaign`.
  Every bucket is the same four fields (`types.ts:265-270`): `conversationCount`,
  `averageFirstResponseSeconds | null`, `averageDurationSeconds | null`, `missedCount`.
- `byOperator` additionally carries `operatorName` (nullable — the console falls back to the
  truncated id, `OperatorAnalyticsPage.tsx:71-73`) and an absent-able `load`
  (`conversationsHeld`/`standardIntervals`/`additionalIntervals`, plus its own `byLoad` cross-tab),
  rendered through `loadCellValue` (`:88-90`) so **"no assignment data" renders as its own value, not
  as `0` and not as the em dash that means "nothing to average"**.
- **Two notes on that page are content, not decoration**: `analyticsLoadIntervalNote`
  (`:602` — `Held` counts conversations, `Standard`/`Additional` count intervals) and
  `analyticsTrafficSourceNote` (`:618` — referrer and campaign are what the browser reported, never a
  verified fact).
- The page loads the server's default window on first paint (`:249-268`), renders the range the
  **response** echoes (`:559-564`), and tells exactly one failure apart: `Analytics.InvalidRange`
  gets its own message, everything else the generic one (`:231-237`).

### What the mockup does and does not say

The mockup draws the five **only** as graph nodes and overflow edges — `MyNumbers -- "⋮ ·
site:configure" --> SiteStats` and three siblings, plus `-- "⋮ · calendar:configure" --> Reveals`.
**It draws no frame for any of the five report screens, and none for the Аналитика landing screen
either.** So the menu, its labels («По сайту», «Конверсия», «По меткам», «Воронка записи», «Показы
телефонов») and the per-entry gate are quoted design; the *content* of this screen is not, and is
scoped below from the console's real data shape plus `scope-inventory.md` §5's own suggestion
(date-range chips, stat cards, one horizontally-scrollable table per breakdown) — which the shape
above does support: the overall bucket is four numbers, and every breakdown is a genuinely separate
dimension.

## Scope

One promise: **Аналитика carries an overflow, and «Аналитика сайта» behind it shows the site's own
numbers for a chosen window.**

1. **An overflow on Аналитика's app bar**, built as `ConversationListOverflowMenu` is, holding
   **only entries whose screen exists** — this wave, exactly one («По сайту»), drawn only while
   `permissions.holds("site:configure")`. `buildMoreRows`'s own rule (`MoreScreen.kt:138-143`),
   restated for this menu: a row exists for a screen that exists. An operator without
   `site:configure` sees no `⋮` at all, because the menu would be empty — hidden, not disabled,
   matching the console's own hide-rather-than-mute nav (`consoleNav.ts:189`).
2. **Sub-navigation one level deep**, `MoreScreen.kt:64-69`'s shape, with a `BackHandler` enabled
   only while a report is open so back lands on Аналитика — `navigation.md` back-contract clause 2.
3. **A `SiteAnalyticsApi` port in `:core:domain` and a Ktor adapter in `:core:network`**, on the
   existing `apiBaseUrl`, built the way `ConversationsApi`/`KtorConversationsApi` are — the whole
   status-code-to-meaning mapping in the adapter, a sealed result in the port, no Ktor type crossing
   the boundary.
4. **The screen**: a date-range control that loads the server's default window with no interaction,
   the range shown always taken from the response's own `from`/`to`; the `overall` bucket as stacked
   stat cards with the previous-window comparison beside it; then `byChannel`, `byOperator`,
   `byReferrer` and `byCampaign` as four separately-captioned, horizontally-scrollable tables.
5. **The two honesty notes survive verbatim in meaning** — the interval-vs-conversation unit note
   under the operator table, and the "this is what the browser reported" note above referrer and
   campaign. So does the three-way distinction between a real `0`, "nothing to average" and "no
   assignment data at all".
6. `Analytics.InvalidRange` keeps its own message; every other failure renders as a refusal with a
   retry and never as a raw exception class name (`26-59`).

## Out of scope

- **The other four reports.** `26-71` (конверсия), `26-72` (метки), `26-73` (воронка записи),
  `26-74` (показы телефонов). Each adds its own entry to the menu this item builds; none of them
  re-litigates the menu.
- **The operator × load-bucket cross-tab** (`load.byLoad`, `OperatorAnalyticsPage.tsx:406-439`). The
  three `load` *columns* port, because they are three more fields on a row this screen already draws;
  the flattened per-(operator, bucket) second table is a different pair of dimensions that nobody has
  asked to read on a phone. If it is wanted later it gets its own number then, not a silent
  half-port now.
- **Any chart.** Nothing in the console draws one for this data (`26-57`'s own Out of scope states
  the same rule for the same reason).
- **Changing the bottom-bar gate.** Аналитика is drawn unconditionally (`BottomDestination.kt:49-56`)
  and stays that way — «Мои показатели» is ungated on purpose; only the overflow is gated.

## Done when

- [x] An operator holding `site:configure` opens Аналитика, taps `⋮`, and reaches «По сайту» — the gate
      is asserted in `AnalyticsReportTest`; the tap-through is a UI mechanism, not re-tested separately.
- [x] An operator **without** `site:configure` sees no `⋮` on Аналитика at all — asserted for `Known`,
      `Known(∅)` and `Unknown` in `AnalyticsReportTest`.
- [x] The screen loads the server's default window with no interaction, and the range it displays is
      the response's own `from`/`to` — asserted in `SiteAnalyticsViewModelTest`.
- [x] A breakdown with no rows says so for itself — `BreakdownTable` draws its own caption + empty text
      per dimension.
- [x] An operator row with no `load` renders its own "no data" value, distinct from a real `0` and from
      the null-average value — asserted at the adapter and view-model level.
- [x] The interval-vs-conversation note and the browser-reported-traffic note are both on the screen.
- [x] Back from «По сайту» returns to Аналитика via `AnalyticsTabHost`'s own `BackHandler`.
- [x] An invalid range renders its own distinct message (`Analytics.InvalidRange` → its own arm, no
      retry offered).
- [x] `./gradlew ktlintCheck lint test assembleDebug` green — 501 tests, 0 failures, independently
      re-verified with `--rerun-tasks`.
- [~] Checked on a real device, in both light and dark, against a site with real conversation history
      and one whose window is empty — not done by the managing session yet.
