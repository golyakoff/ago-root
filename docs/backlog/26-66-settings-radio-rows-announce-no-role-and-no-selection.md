# 26-66 · Settings' radio rows announce no role and no selection

- **Stage**: 26
- **Status**: done — merged as [ago-android#58](https://github.com/golyakoff/ago-android/pull/58)
- **Found**: 2026-09-23, reading `SettingsScreen`'s two selectable rows against `ago-android` `main`
  at `b099282`.

## Found

Settings has two groups of radio rows — Тема (system / light / dark) and Текущий сайт — and both are
built the right way for touch and the wrong way for a screen reader.

The `RadioButton` in each row is passed `onClick = null`, so the enclosing `Row` owns the click and
the whole row is one tap target. That is the recommended Material 3 shape and the file says so
(`SettingsScreen.kt:190-194`). But the `Row` is made clickable with `Modifier.selectable(selected,
onClick)` and **no `role`** — so the merged node has a selected state and no idea what kind of control
it is. TalkBack announces the label and, at best, "selected"; it never says "radio button", and it
never says "1 of 3".

For a settings screen whose entire content is two mutually-exclusive choices, that is the one thing a
listener needs to know.

## What is actually true today, confirmed against real code

- `ThemeModeRow` (`SettingsScreen.kt:176-198`):

  ```kotlin
  Modifier
      .fillMaxWidth()
      .selectable(selected = selected, onClick = onSelected)
      .padding(horizontal = 16.dp, vertical = 4.dp)
  ```

  `androidx.compose.foundation.selection.selectable` takes a `role: Role?` parameter that defaults to
  `null`. It is not passed here.
- `SiteRow` (`SettingsScreen.kt:208-231`) — the same, plus `enabled = !switching`:
  `selectable(selected = selected, enabled = enabled, onClick = onClick)`, again with no role.
- Neither group is wrapped in a `selectableGroup()`, which is what supplies the "N of M" position
  announcement for a set of mutually-exclusive options.
- The site row's second line goes through `IdentifierText`
  (`ui/components/IdentifierText.kt:26-36`) — eight monospace hex characters, spoken character by
  character or as a nonsense word depending on the engine. It is there to be read with the eyes or
  dictated aloud by a human, not to be announced as part of a control's name.
- The app does already get this right where it thought about it: `HubConnectionDot`
  (`ui/components/HubConnectionDot.kt:66-74`) carries a real `contentDescription` on a bare `Box`,
  with a doc comment explaining that a coloured circle is invisible to a screen reader.

## Scope

One promise: **Settings' two choice groups announce what they are and which option is chosen.**

1. Both `selectable` calls pass `role = Role.RadioButton`.
2. Each group is wrapped in `Modifier.selectableGroup()` so the position within the set is announced.
   For Тема that is the `ThemeMode.entries` items; for Текущий сайт, the tenancy items
   (`SettingsScreen.kt:118-119`, `:124-131`).
3. The site row's identifier does not have to be read out as part of the control's name. Decide
   whether to exclude it from the merged semantics or to give the row an explicit description that
   names the site and omits the id, and say which in the report — the id is genuinely useful to a
   sighted operator and genuinely noise to a listener.
4. The disabled state while a site switch is in flight is announced as disabled, which
   `selectable(enabled = …)` already supplies once the role is there.

## Out of scope

- **The back arrow.** `26-43` replaces the literal `Text("←")` with a real icon **and** the
  `action_back` content description; nothing is left for this item to do there.
- **The section headers** — `26-44` rebuilds them as the mockup's `.slabel` and is the item that
  decides whether they become semantic headings.
- **The sign-out `TextButton`** and the About lines. Both are ordinary labelled text and read
  correctly today.
- **Touch targets.** Checked while filing: `RadioButton` carries Material 3's own 48dp minimum
  interactive size, so both rows clear the target guidance despite the 4dp/8dp padding. Nothing to
  fix.

## Done when

- [x] With TalkBack on, each theme row is announced as a radio button, with its selected state and its
      position in the group.
- [x] The same for each site row, including the disabled announcement while a switch is in flight.
- [x] The site's short identifier is not read as part of the control's name.
- [x] A Compose semantics test asserts the role and the selection on both groups.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.
- [x] TalkBack itself is not installed on the test device — verified instead via `adb shell
      uiautomator dump` reading the real `AccessibilityNodeInfo` tree on the live Settings screen
      (10/10 instrumented tests pass, including two-site fixture data for the site group).
