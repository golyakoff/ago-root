# 26-43 · The Settings screen's back arrow is still a literal «←»

- **Stage**: 26
- **Status**: done — merged as [ago-android#45](https://github.com/golyakoff/ago-android/pull/45)
- **Found**: 2026-09-23, reading the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) against `ago-android` `main` at `ad2859b`.

## Found

`26-23` removed exactly this from the app — twice, in the same change — and one call site was not in
the app yet when it did.

The mockup's back control is a vector, the same one on every screen that has one:

```html
<symbol id="i-back" viewBox="0 0 24 24"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></symbol>
```

drawn at `svg.i{width:21px; height:21px; stroke-width:1.8; stroke-linecap:round}` inside an
`.iconbtn{width:38px; height:38px; border-radius:50%}`.

`SettingsScreen` draws the character `←` in a headline text style instead.

## Why this survived `26-23`

`26-23`'s own doc comments name both places it fixed:

- `ThreadScreen.kt:182-184` — "`26-23`: the mockup's `i-back`, a real vector - this used to be a
  literal `Text("←")`, which is also what `AppShellScreen`'s retired `BottomDestination.emoji()` cited
  as its own precedent. Both are gone."
- `AppShellScreen.kt:326-332` — "This replaces `emoji()`, which returned a plain-text emoji per
  destination and whose own doc comment cited `ThreadScreen`'s `\"←\"` as the precedent for 'this app's
  established convention': both were the same gap, and `26-23` closed both, so there is no such
  convention left to appeal to."

Both were true and both landed. `26-17`'s Settings screen was authored against that same retired
convention in parallel, and reintroduced it on a screen `26-23` had never seen. This is the third and
last instance: `grep` for a bare arrow character across `app/src/main/kotlin` finds exactly one.

## What is actually true today, confirmed against real code

- `app/src/main/kotlin/ago/chat/android/shell/SettingsScreen.kt:108-112`:

  ```kotlin
  navigationIcon = {
      IconButton(onClick = onBack) {
          Text(text = "←", style = MaterialTheme.typography.headlineSmall)
      }
  },
  ```

- The vector it should be drawing already exists and is already used by the only other back button in
  the app: `AgoIcons.Back` (`ui/icons/AgoIcons.kt:140`), transcribed from the mockup's own `#i-back`
  symbol by `26-23`.
- The accessible name already exists too: `R.string.action_back` («Назад»,
  `app/src/main/res/values/strings.xml`), added by `26-23` for precisely this reason — its own comment
  there: "A text button carried its own label for a screen reader for free; an icon button does not,
  so the label has to exist somewhere - and a `contentDescription` is where." The literal `←` here has
  no `contentDescription` at all, so this is an accessibility gap as well as a visual one: a screen
  reader today announces this control as the character it draws.

## Scope

One promise: **the Settings screen's back control is the mockup's back control.**

Replace the `Text("←")` with `Icon(imageVector = AgoIcons.Back, contentDescription =
stringResource(R.string.action_back))` inside the existing `IconButton`, matching `ThreadScreen.kt:185-190`
exactly rather than approximating it. No new icon, no new string, no new component.

## Out of scope

- Everything else on the Settings screen. The section-label treatment is `26-44`; the screen's content
  and behaviour (`26-17`) are correct and untouched.
- Auditing for other literal-character controls. There is one, and this is it — but if the change
  turns up another, file it rather than folding it in.

## Done when

- [x] Settings' back control draws `AgoIcons.Back` and carries `R.string.action_back` as its
      `contentDescription`.
- [x] TalkBack announces it as «Назад» — `SettingsScreenTest.backArrowCallsOnBack` finds it by that
      `contentDescription` (rewritten in the same change; the real CI regression this caused and its
      fix are recorded in the PR).
- [x] Back from Settings still lands on the Ещё list (back-contract clause 2, `26-16`) — the existing
      instrumented coverage still passes.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.

Confirmed live on the real device (`F6VCHEZDAMRCPNJZ`): Settings draws the real vector back arrow in
both light and dark.
