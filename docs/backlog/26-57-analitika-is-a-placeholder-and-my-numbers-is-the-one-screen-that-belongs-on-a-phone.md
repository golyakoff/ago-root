# 26-57 · Аналитика is a placeholder, and «Мои показатели» is the one report that belongs on a phone

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, reading `ago-console/src/pages/MyNumbersPage.tsx` and
  `ago-console/src/api/conversationsApi.ts` against `ago-android` `main` at `b099282`, with the
  approved mockup Artifact ("AGO Chat для Android", `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`)'s own
  graph (`subgraph A["4 · Аналитика"]`, `MyNumbers["Мои показатели"]` as its landing screen).

## Found

Of the six screens the console files under Аналитика, five are a date-range form over several tables
of three numbers, read at a desk while arguing about a number. **One is different**, and both
`consoleNav.ts` and `scope-inventory.md` single it out for the same reason: «Мои показатели» is
ungated, it is about the person reading it, and it is the one an operator would genuinely open on a
phone between conversations.

`scope-inventory.md` §5 puts it plainly: "Ungated on purpose — a grant here would be something a
tenant could withhold from its own staff. It is also the one analytics screen that genuinely belongs
on a phone, and it is in Phase 1 for that reason."

This item is that one screen. The other five are `26-58`.

## What is actually true today, confirmed against real code

- `app/src/main/kotlin/ago/chat/android/shell/PlaceholderScreens.kt:64-71`, wired at
  `AppShellScreen.kt:285`. The destination is always drawn
  (`BottomDestination.kt:49-56` adds Analytics unconditionally) — so unlike Записи, there is no gate
  question to answer here at all.
- The read is one call on the chat API this app already talks to: `fetchOwnAnalytics`
  (`ago-console/src/api/conversationsApi.ts`), taking an optional `from`/`to` and returning
  `{ bucket, load, conversion, from, to }` (`MyNumbersPage.tsx:103-107`). No new base URL, no new
  permission, no hub traffic.
- **Both range bounds are optional and the server defaults the window**
  (`conversationsApi.ts:421-431`): omit them and the handler applies its own thirty-day default. The
  response's own `from`/`to` is "the only honest source for what range did this actually report on" —
  never the inputs, which may be blank.
- The console loads on first paint with no interaction, because there is no permission to wait on
  (`MyNumbersPage.tsx:121-124`).
- **Three independent "no data yet" states, not one** (`MyNumbersPage.tsx:69-73`): `bucket` is always
  present and zero-filled, while `load` and `conversion` are each separately absent-able, and the page
  says which half is missing rather than showing one page-wide empty state. That distinction is the
  screen's own content and must survive the port.
- Exactly one failure is told apart from the rest: `Analytics.InvalidRange` gets its own message;
  everything else gets the generic one (`MyNumbersPage.tsx:108-114`). That is a real, deliberate
  branch, not laziness.

## Scope

One promise: **Аналитика shows this operator their own numbers for a chosen window.**

1. An `OwnAnalyticsApi` port in `:core:domain` and a Ktor adapter in `:core:network`, on the existing
   `apiBaseUrl`, built the way `ConversationsApi`/`KtorConversationsApi` are.
2. The screen loads the server's default window on first composition, with no range chosen, and
   renders the range **the response reports**, not the one the inputs hold.
3. Stacked stat cards rather than a table — the mockup's own `.card` + `.kv` shape, which its §06
   frames already establish (`«Дней перенарезано» · 18` and friends). A phone has no column for a
   three-column table of numbers.
4. A date-range control, and the three absent-able sections each saying for themselves whether they
   have data.
5. `Analytics.InvalidRange` keeps its own message; every other failure renders as a refusal with a
   retry and never as a raw exception class name (`26-59`).

## Out of scope

- **The five `site:configure` reports** — `/analytics/site`, `/analytics/conversion`,
  `/analytics/tags`, `/analytics/booking-flow`, and `/calendar/phone-reveals`. `26-58` is the item
  that decides what happens to them; this one does not pre-empt it, and deliberately does not add an
  overflow menu that would have to point at screens that do not exist.
- **Any chart.** Nothing in the console draws one for this data and inventing a visual encoding for
  numbers nobody has asked to see that way is not this item's decision.
- **Comparing against a previous window.** `OperatorAnalyticsPage` holds a `previousOverall`
  (`:198`); `MyNumbersPage` does not, and adding it here would make the phone claim something the
  console's own equivalent screen does not.

## Done when

- [ ] Аналитика opens on the server's default window with no interaction and shows this operator's own
      numbers.
- [ ] The range shown is the response's own `from`/`to`.
- [ ] Each of the three sections says for itself when it has no data; there is no single page-wide
      empty state.
- [ ] An invalid range renders its own distinct message.
- [ ] An ordinary operator with no `site:configure` sees the screen in full — nothing on it is gated.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
- [ ] Checked on a real device against an operator with real conversation history, in both light and
      dark.
