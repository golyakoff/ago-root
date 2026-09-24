# 26-71 · «Отчёт по конверсии» is not on the phone

- **Stage**: 26
- **Status**: done — merged as [ago-android#94](https://github.com/golyakoff/ago-android/pull/94).
- **Found**: 2026-09-23, reading `ago-console/src/pages/ConversionReportPage.tsx`,
  `ago-console/src/api/conversationsApi.ts` and `ago-console/src/realtime/protocol/types.ts` against
  `ago-android` `main` at `b099282`, with the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`)'s own `MyNumbers -- "⋮ · site:configure" --> Conversion`.

## Found

The second of the five reports `26-58` decided to port: what the operators recorded as the outcome
of a conversation, and what share of the recorded ones converted. `26-70` builds the overflow menu
this hangs off; this item adds one entry to it and the destination behind it.

## What is actually true today, confirmed against real code

- `ago-console/src/App.tsx:380` → `ConversionReportPage`, drawn in the nav at
  `consoleNav.ts:191`, gated `site:configure` (and re-checked server-side).
- The read is `GET /api/v1/conversations/conversion-report` (`conversationsApi.ts:528`), **both
  bounds optional** (`ConversionReportParams`, `:510`) — omit them and
  `GetConversionReportForSiteHandler` applies its own thirty-day default.
- **The bucket is six fields, not a rate** (`types.ts:435-442`): `convertedCount`,
  `notConvertedCount`, `followUpNeededCount`, `unsetCount`, `recordedCount`, and
  `conversionRate | null` — `null` when nothing was recorded, never `0`.
- The response (`types.ts:462`) is `from`/`to`, `overall`,
  `previousFrom`/`previousTo`/`previousOverall`, and `byOperator` — one dimension only.
  `ConversionOperatorBucketDto` (`types.ts:451-456`) is `operatorId`, `bucket`, and a nullable
  `operatorName`; the console falls back to the truncated id.
- **`unsetCount` is the honesty field and is rendered as its own column**
  (`ConversionReportPage.tsx:210-214`) — conversations nobody recorded an outcome for. So is the
  banner: `conversionReportNotAVerifiedSaleBanner` renders as an `Alert tone="info"` above
  everything (`:274`), because every number here is what an operator *chose to record*
  (`types.ts`'s own remarks on `ConversionBucketDto`).
- The rate is formatted as a percentage **with its own fraction spelled out** —
  `"12.3% (converted of recorded)"` (`:52-54`), not a bare percentage.
- **Three date presets, resolved client-side**: «этот месяц» / «прошлый месяц» / «последние 30 дней»,
  from `src/time/rangePresets.ts` (`:19`, used at `:277-286`). There is no server-side preset
  concept; a preset is resolved into concrete `from`/`to` before the request.
- Same failure branching as the site report: `Conversation.Forbidden` and `Analytics.InvalidRange`
  each get their own message, everything else the generic one (`:124-128`).

### What the mockup does and does not say

The mockup names this destination («Конверсия») and its gate, as a graph node and an overflow edge,
and **draws no frame for the screen itself**. The layout below is scoped from the data shape above
plus `scope-inventory.md` §5's own suggestion, which fits: one overall bucket of five counts and a
rate is stat-card material, and `byOperator` is one table.

## Scope

One promise: **«Отчёт по конверсии» shows the site's recorded conversation outcomes for a chosen
window.**

1. A `ConversionReportApi` port in `:core:domain` and a Ktor adapter in `:core:network`, on the
   existing `apiBaseUrl`, built the way `ConversationsApi`/`KtorConversationsApi` are.
2. A new entry in Аналитика's overflow («Конверсия»), gated `site:configure`, added to the menu
   `26-70` builds; the destination is one level deep with the same `BackHandler` contract.
3. The screen loads the server's default window with no interaction and renders the range the
   **response** reports.
4. **The caveat banner is on the screen, above the numbers** — not a footnote, matching the console's
   own `Alert`. A rate shown without it is the defect this report was built to avoid.
5. The overall bucket as stat cards: the four counts including `unsetCount`, then the rate with its
   own converted-of-recorded fraction, then the previous-window comparison. `conversionRate === null`
   renders its own "no data" value, never `0%`.
6. `byOperator` as one horizontally-scrollable table, `operatorName` where present and the truncated
   id where not — never a fabricated label.
7. The three date presets port as a chip row; `Analytics.InvalidRange` keeps its own message, and
   every other failure renders as a refusal with a retry (`26-59`).

## Out of scope

- **The overflow menu itself** — `26-70`.
- **Recording or changing an outcome.** This is a read. The write lives on a conversation
  (`GET`/`PUT /api/v1/conversations/{id}/outcome`, `conversationsApi.ts`'s own
  `fetchConversationOutcome`) and is not this screen's.
- **Any chart**, for the reason `26-57` already states: nothing in the console draws one for this
  data.

## Done when

- [x] An operator holding `site:configure` reaches «Конверсия» from Аналитика's overflow and sees the
      site's recorded outcomes for the server's default window with no interaction.
- [x] The not-a-verified-sale caveat is visible on the screen beside the numbers, not hidden behind a
      scroll of tables.
- [x] `unsetCount` is shown as its own figure, never folded into "not converted".
- [x] A `null` conversion rate renders its own value, distinct from `0%`.
- [x] An operator row with no name renders the truncated id, never an invented label.
- [x] Each of the three presets produces the range the response then echoes back.
- [x] An invalid range renders its own distinct message.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.
- [~] Checked on a real device, in both light and dark, against a window with recorded outcomes and — delivered and CI-green (build/unit/ktlint/lint); on-device check pending, phone disconnected 2026-09-25.
      one with none at all.
