# 26-28 · The shell counts the status-bar inset twice, leaving a blank band above every screen

- **Stage**: 26
- **Status**: done — merged as `ago-android#35`. Verified against real code:
  `AppShellScreen.kt`'s `Scaffold.contentWindowInsets` excludes the top edge (letting each screen's own
  `TopAppBar` draw it exactly once) while keeping and consuming the bottom edge via
  `Modifier.consumeWindowInsets(padding)` on the `NavHost`, with a comment on the `Scaffold` itself
  saying which edge it owns.
- **Found**: 2026-09-22, by the author, on his own phone, comparing the real `ago-android` build
  (`26-23` installed) against the approved mockup Artifact ("AGO Chat для Android"). In his own words:
  "Над диалогом гигантское пустое место до статусбара телефона - почему оно не используется?"

## What is actually true today, confirmed against real code

The gap is not empty padding somebody chose. It is the system status-bar inset applied **twice**, by
two nested `Scaffold`s neither of which knows about the other:

- `MainActivity.onCreate` calls `enableEdgeToEdge()`, so the app draws behind the status bar and every
  inset has to be consumed exactly once by somebody.
- `AppShellScreen.kt`'s `AppShellContent` draws a `Scaffold` with a `bottomBar` and **no `topBar`**.
  Material 3's `Scaffold` defaults `contentWindowInsets` to `ScaffoldDefaults.contentWindowInsets`
  (system bars), so the `PaddingValues` it hands its content already carries the full status-bar
  height as `top`. That value is applied: `NavHost(..., modifier = Modifier.padding(padding))`.
- Every destination inside that `NavHost` then draws **its own** `Scaffold` with **its own**
  `TopAppBar`, and a Material 3 `TopAppBar` applies `TopAppBarDefaults.windowInsets` (system bars,
  top) of its own. `Scaffold` does not *consume* the insets it reports, so that inner bar adds the
  same status-bar height a second time.

Net effect: one full status-bar height of blank surface between the real status bar and the
`TopAppBar`'s own title. This is **not specific to Диалоги** — every destination in the shell draws
the same shape and therefore has the same band:

| File | Line | Screen |
|---|---|---|
| `conversations/ConversationListScreen.kt` | 159–162 | Диалоги |
| `shell/PlaceholderScreens.kt` | 36 | Записи, Команда, Аналитика |
| `shell/MoreScreen.kt` | 82 | Ещё |
| `shell/SettingsScreen.kt` | 104–106 | Настройки |
| `thread/ThreadScreen.kt` | 170–173 | the thread |

**Correction, found while fixing this and recorded rather than quietly dropped**: this item first said
"only the top double-counts". That is wrong. The bottom double-counts too, just less visibly. An inner
screen has no `bottomBar` of its own, so Material 3 gives its content a bottom padding of
`contentWindowInsets.getBottom()` — the navigation-bar inset — even though the outer `Scaffold` has
*already* lifted the whole `NavHost` above the `NavigationBar`. Compose insets are window-relative
until somebody consumes them, and nobody did. So the fix has to answer both edges, not one.

## Scope

One promise: **no screen in the shell shows a blank band under the system status bar.**

The fix belongs in the one place that knows both `Scaffold`s exist — `AppShellContent` — not spread
across six screens as six `WindowInsets(0)` overrides that each depend on being nested. Either the
outer `Scaffold` stops reporting a top inset to the `NavHost` (letting each screen's own `TopAppBar`
draw into the status bar, which is what an edge-to-edge app is supposed to do and what the mockup
draws), or the shared inset is consumed explicitly so it cannot be applied twice. Whichever shape is
chosen, say in the code comment which `Scaffold` owns which edge, because the next screen added to
this `NavHost` will inherit the answer silently.

Verify on a real device or emulator with a visible status bar — a Compose preview has no insets at
all and will look correct either way. Both orientations, and both a gesture-navigation and a
three-button-navigation device, since those change the bottom inset and would catch an over-correction
that removes the bottom padding too.

## Out of scope

- Anything about what the top bar *contains* — that is `26-32`.
- Anything about the row's own contents — that is `26-30`.

## Done when

- [x] The status-bar inset is applied exactly once, decided in `AppShellContent`'s `Scaffold`, with a
      comment on it saying which edge it owns.
- [x] Диалоги, the thread, Ещё, Настройки and the three placeholder screens each start their content
      directly under the system status bar (the outer `Scaffold` no longer reports a top inset, so
      each screen's own `TopAppBar` draws it exactly once).
- [x] The bottom navigation bar edge is kept and explicitly consumed
      (`Modifier.consumeWindowInsets(padding)` on the `NavHost`), so no inner screen double-counts it.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.
