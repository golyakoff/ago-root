# 26-77 · A unified header, and a real account menu instead of a stray kebab

- **Stage**: 26
- **Status**: done — merged as [ago-android#64](https://github.com/golyakoff/ago-android/pull/64), with
  four live-device corrections found by the author right after merge and fixed in a follow-up,
  [ago-android#65](https://github.com/golyakoff/ago-android/pull/65): the presence dot was clipped at
  the avatar's own corner (a `CircleShape` clip on the wrong box), the menu header's own avatar was
  drawn larger than the trigger and carried a redundant second presence dot, Настройки kept its own
  "Выйти" button duplicating the new menu's, and Тема stayed a column of radio rows instead of the
  mockup's own segmented tabs. Both PRs independently verified by the managing session.
- **Found**: 2026-09-23, by the author, comparing his own real device against the mockup Artifact
  ("AGO Chat Design", `https://claude.ai/code/artifact/8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) — the
  top-right corner of the app bar (online dot, kebab menu) is a different, ad-hoc shape on every
  screen, designed together with the author over several rounds in chat before being drawn into that
  mockup Artifact's new section "08 · Аккаунт и шапка".

## What is actually true today, confirmed against real code (`ago-android`)

### The header is not a shared component — every screen builds its own

`AppShellContent`'s own doc comment (`shell/AppShellScreen.kt:214-243`) states the rule explicitly:
"this `Scaffold` owns the bottom edge and the horizontal edges; **every destination inside its
`NavHost` owns the top edge**." There is no shared top-bar composable. Confirmed by reading every
top-level destination directly:

| Screen | File | Online dot | Menu/Sign-out |
|---|---|---|---|
| Диалоги | `conversations/ConversationListScreen.kt` | yes (`HubConnectionDot`) | yes (`ConversationListOverflowMenu` — today, only "Выйти") |
| Команда | `team/TeamChatScreen.kt:96-101` | yes | **no** — no sign-out reachable from here at all today |
| Тред (открытый диалог) | `thread/ThreadScreen.kt:210-233` | yes | no (back-arrow header, correct — a drill-in screen, out of scope here) |
| Записи | `bookings/BookingsScreen.kt:89` | no | no — bare `TopAppBar(title=...)` |
| Ещё | `shell/MoreScreen.kt:83` | no | no — bare `TopAppBar(title=...)` |
| Аналитика | `shell/PlaceholderScreens.kt:53` | — | — (still an honest "coming soon" placeholder, out of scope here) |

Nobody designed this inconsistently on purpose — it accreted, one screen at a time, as each was built.

### `MoreScreen.kt` already has the exact machinery this item needs

`shell/MoreScreen.kt:29-51`'s own doc comment says two things worth quoting directly:

1. `SETTINGS_ROW_ID` was drawn in "Ещё" as **"a stated exception… even if that row currently points
   nowhere (or a placeholder) since `26-17` hasn't landed"** — Settings living in "Ещё" was always
   documented as a temporary placement, not a permanent architectural home. Moving it into the account
   menu resolves that stated stopgap; it does not override a considered decision.
2. `MoreSectionId.Automation` and `MoreSectionId.Administration` **already exist** as enum members,
   and `buildMoreSections` already has the "a section with no rows is not returned at all" filter
   wired up. Only `buildMoreRows()` needs new entries.
3. `PlaceholderDestinationScreen` (`shell/PlaceholderScreens.kt:31-48`) is explicitly kept "as a
   single row's worth of shared shape for whichever destination is next to lose its placeholder" —
   the exact, already-built, already-generic component to point new rows at.

**Consequence for scope**: once Настройки moves out, "Ещё" would show nothing at all (it is the only
row `buildMoreRows()` returns today). The fix is real rows for Автоматизация and Администрирование,
each opening `PlaceholderDestinationScreen` — not a fake/unclickable row, and not an empty tab.

## Scope

One promise: **the five top-level screens share one header shape, and Настройки/Выйти have one real,
consistent place to be reached from — with nothing left broken by moving them there.**

### 1. Two shared header shapes

- **Type A — top-level tab header.** `Title … [screen-specific icons, if any] … Avatar`. Used by the
  five bottom-nav destinations. The avatar is always the rightmost element; a screen that genuinely
  needs its own icon (Диалоги's search) keeps it, to the avatar's left.
- **Type B — drill-in header.** `⟵ Title`. Unchanged from what the thread screen already does — named
  here only so the new Настройки screen follows the same, already-established shape.
- Implementation shape: a small shared composable (e.g. `AccountAvatarAction(hubConnectionState,
  onOpenSettings, onSignOut)`) that each Type-A screen's own `TopAppBar` calls from its `actions` slot
  — the same reuse shape `HubConnectionDot` already is today, extended rather than replaced. Each
  screen keeps owning its own `TopAppBar` (and its own window-inset handling — see `26-28`'s own
  remarks on why that split exists and what broke before it did); nothing moves up into the shared
  `Scaffold` in `AppShellContent`.

### 2. The avatar + presence indicator

- A circle with the operator's initials (first letters of the two words in their display name — "АГ"
  for "Андрей Голяков"). **Derivation rule, to settle during implementation, not guessed here**: first
  letter of the first two space-separated words of the display name; a single-word name uses its first
  one or two letters; empty/unset name falls back to something honest (not blank) — check what
  `AgoAuthSession`/wherever the display name is actually sourced from can guarantee before picking a
  final rule.
- The online/offline dot (today `HubConnectionDot`, a bare colored circle) moves to overlap the
  avatar's own bottom-right corner, with a glow (soft-colored halo) — binding "this dot is about this
  user" rather than two unrelated circles side by side. `HubConnectionDot`'s existing accessibility
  handling (a colored circle needs a `contentDescription`, per its own doc comment) must be preserved
  on whatever composable replaces it.

### 3. The account menu — lean, GitHub-style

- Header: avatar (slightly larger), display name, email/username.
- One navigation item: **Настройки**, with a chevron, opening the existing Settings screen.
- Divider, then **Выйти** — **plain styling, the same color as every other menu item.** (Decided
  2026-09-23: no destructive/danger red. It is an ordinary, fully reversible action — signing back in
  costs nothing — and does not need the visual weight a genuinely destructive action like account
  deletion gets elsewhere in this app.)
- Explicitly **not** in this menu: theme, language, or any other inline control — both already live in
  Настройки (theme) or are out of scope for now (language — see `26-79`).
- Icons: simple line-icon glyphs (Material-style), never emoji.

### 4. "Ещё" gains real Автоматизация/Администрирование rows once Настройки leaves

- `buildMoreRows()` gains entries for `MoreSectionId.Automation` and `MoreSectionId.Administration`
  (the enum members already exist). Row labels for Автоматизация should match the mockup's own
  already-drawn labels ("Готовые ответы", "Автоответ вне смены") where a real future feature is
  already named; Администрирование has no prior mockup content beyond this item's own placeholder
  guess ("Операторы и роли" / "Тариф и оплата") — confirm naming with the author before implementing
  if it matters, or ship the guess and let it be corrected in review.
- Each new row opens `PlaceholderDestinationScreen` until the real screen behind it exists.
- `SETTINGS_ROW_ID`/the Settings row is removed from `buildMoreRows()` entirely — not left duplicated
  in both places.

### 5. Settings screen — unchanged in this item

- **No Язык row in this item.** See `26-79`: the app has no second interface language, no
  `values-en/`, and no runtime locale-switching infrastructure at all today — a working language
  toggle is a real, separate i18n undertaking, not a row that fits inside this item's own promise.
  `SettingsScreen.kt` keeps exactly its current content (Тема, Сайт) for now.

## Out of scope (explicitly, so nobody assumes this item decided them)

- **Все диалоги / Ограниченные посетители's future home.** The mockup Artifact's own "00 · Граф
  переходов" section originally routed Диалоги's kebab to these two site-admin screens
  (`site:configure`-gated), which do not exist in this app yet. Once the avatar replaces that kebab,
  their eventual home is an open question — a second element beside the avatar (shown only for an
  operator holding `site:configure`), or folded into the avatar's own dropdown above a divider.
  **Not decided here.** Does not block this item (neither screen is built yet; today's kebab holds
  only "Выйти", which loses nothing by moving). Whichever item first builds either screen for Android
  must resolve this before adding its own entry point.
- **Команда's missing sign-out**, a real, if minor, pre-existing gap independent of this whole
  redesign — resolved as a side effect once Команда adopts the shared Type-A header, not called out as
  its own separate fix.
- **Язык интерфейса** — `26-79`.
- **The segmented-tab checkmark** — `26-78`, a real app/mockup divergence unrelated to this item
  (Material 3's own default check icon on `SegmentedButton`; the mockup never drew one).

## Done when

- [x] A shared header composable (`AccountAvatarAction`) exists and is used by all five top-level
      destinations (Диалоги, Записи, Команда, Аналитика, Ещё) — confirmed by reading each screen's own
      `TopAppBar` call site directly, not just the composable's own existence.
- [x] Every one of those five screens shows the avatar (initials + presence dot with glow) at the
      rightmost position of its app bar; Диалоги's own search icon stays to its left. The dot's own
      clipped-corner bug (found live by the author right after merge) is fixed in the follow-up,
      ago-android#65.
- [x] Tapping the avatar opens the lean account menu: header (avatar, name, email), "Настройки" with a
      chevron, divider, "Выйти" — the same, non-danger color as "Настройки". The header's own avatar
      was oversized and carried a redundant second presence dot in the first pass; both fixed in
      ago-android#65, per the author's own live-device review.
- [x] "Настройки" opens the real `SettingsScreen` (Type B header). Content is not literally unchanged
      as first written here — the follow-up PR also removed Settings' own now-duplicate "Выйти" button
      and turned Тема into the mockup's own segmented tabs instead of a column of radio rows — both
      corrections the author asked for on the same live-device pass, not scope this item's own text
      anticipated, but squarely in its spirit (one real account/settings surface, not two).
- [x] "Выйти" from the new menu does what `ConversationListOverflowMenu`'s "Выйти" did — same
      `onSignOut` callback plumbing, confirmed by reading the diff; no regression in the sign-out flow
      itself.
- [x] `ConversationListOverflowMenu` is deleted outright (confirmed no other caller before removal);
      Команда gained a real sign-out path for the first time, having had none before this item.
- [x] "Ещё" shows Каналы (unchanged) plus real Автоматизация and Администрирование rows, each opening
      `PlaceholderDestinationScreen`; the old single "Настройки" row is gone.
- [x] `HubConnectionDot`'s accessibility behavior is preserved — confirmed by the real CI Android
      emulator actually executing `AccountAvatarActionTest.thePresenceDotStillSpeaksItsConnectionState`
      and its eight siblings (all 9/9 passed on `emulator-5554`, ago-android#64's own CI run), not just
      compiled.
- [x] `./gradlew ktlintCheck lint test assembleDebug assembleDebugAndroidTest` green on both PRs —
      independently re-verified by the managing session each time, including a full CI-emulator
      instrumented run.

## Where the visual spec lives

Mockup Artifact "AGO Chat Design" — `https://claude.ai/code/artifact/8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`,
section "08 · Аккаунт и шапка": the lean account-menu popover, and the new Настройки screen shape
(Тема/Сайт unchanged; a Язык row is drawn there as the aspirational target design for `26-79`, not a
promise this item makes). Диалоги, both Записи tabs, and Ещё show the avatar+presence element in
place of the old kebab/nothing.
