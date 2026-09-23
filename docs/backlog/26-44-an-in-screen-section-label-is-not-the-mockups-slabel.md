# 26-44 · An in-screen section label is not the mockup's `.slabel`

- **Stage**: 26
- **Status**: done — merged as [ago-android#45](https://github.com/golyakoff/ago-android/pull/45)
- **Found**: 2026-09-23, reading the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) against `ago-android` `main` at `ad2859b`.

## Found

Every screen in the mockup that groups rows under a heading uses one class for that heading, and it is
deliberately the quietest text on the screen:

```css
.slabel{
  font-size:11px; font-weight:800; letter-spacing:.1em; text-transform:uppercase; color:var(--ink-faint);
  padding:16px 16px 7px;
}
```

Small, very bold, letterspaced, uppercase, and in the *faintest* ink the palette has — a label that
organises without competing. The mockup uses it on the Ещё screen (`Каналы`, `Автоматизация`), on the
notifications screen (`Каналы уведомлений`, `Когда не беспокоить`) and inside the visitor sheet
(`Контактные данные`).

The app draws its section headings in `labelLarge` — 13sp, medium weight, mixed case, no letterspacing
— coloured `primary`, which in this scheme is the brand violet. That is nearly the opposite instrument:
the loudest colour on the screen, at body-ish size, for the text that is supposed to recede. On
Settings, where three of them sit above short lists, the violet headings read as the most important
thing on the screen.

## What is actually true today, confirmed against real code

Two call sites, one shape, written independently by two items:

- `app/src/main/kotlin/ago/chat/android/shell/SettingsScreen.kt:166-174`:

  ```kotlin
  @Composable
  private fun SectionHeader(text: String) {
      Text(
          text = text,
          style = MaterialTheme.typography.labelLarge,
          color = MaterialTheme.colorScheme.primary,
          modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
      )
  }
  ```

  drawn three times — `settings_theme_section` («Тема»), `settings_site_section` («Текущий сайт»),
  `settings_about_section` («О приложении») — at `:117`, `:123` and `:144`.

- `app/src/main/kotlin/ago/chat/android/shell/MoreScreen.kt:85-92`, the same five properties inlined
  rather than shared:

  ```kotlin
  item(key = "header-${section.name}") {
      Text(
          text = stringResource(section.labelRes),
          style = MaterialTheme.typography.labelLarge,
          color = MaterialTheme.colorScheme.primary,
          modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
      )
  }
  ```

  **This one draws nothing today.** `buildMoreRows()` (`MoreScreen.kt:140-143`) returns exactly one
  row and it is ungrouped, so `buildMoreSections` filters all three sections away — that file's own
  doc comment explains why that is correct rather than a bug. It is still the copy that the first real
  Каналы/Автоматизация screen will inherit, silently, which is the reason to fix both now rather than
  fix one and leave a divergent twin waiting.

- The colour the mockup asks for exists and is already bound: `--ink-faint` is
  `AgoInkFaintLight`/`AgoInkFaintDark` (`ui/theme/Color.kt:27`, `:35`). `ui/theme/Theme.kt` does not
  currently bind it to a `ColorScheme` role — check whether it should, or whether this composable
  reads it directly the way `HubConnectionDot` reads `AgoLive` (`ui/components/HubConnectionDot.kt:83`,
  with its own stated reason for bypassing the scheme). Either is defensible; say which and why.
- `11px` has no token behind it — this app's type scale bottoms out at 12sp
  (`ui/theme/Type.kt:70-71`, `labelMedium`/`labelSmall`). Use the 12sp role and lift weight, tracking
  and case, rather than introducing an untraceable `11.sp`; that is the same rule
  `ConversationRowIdentityLine` states for the mockup's own `14.5px`.

## Scope

One promise: **a section label inside a screen is drawn the mockup's way, once.**

1. One shared composable for it — neither screen owns a private copy. Where it lives is the item's own
   small decision (`ui/components/` alongside the other shared pieces is the obvious home); what
   matters is that there is exactly one.
2. It renders the mockup's `.slabel`: uppercase, heavy weight, `.1em` tracking, `--ink-faint`, and the
   asymmetric `16dp / 16dp / 7dp` padding — not the symmetric `8dp` vertical both copies use now.
   Uppercase by CSS `text-transform` means the *string resources stay in sentence case* and the
   composable does the transformation; do not shout in `strings.xml`.
3. Both call sites use it. Delete the inlined copy in `MoreScreen`.

## Out of scope

- Material 3's `TopAppBar` titles, which are a different thing entirely and already correct.
- The Ещё list *row* — the mockup's own row carries a supporting line and a trailing chevron
  (`#i-chev`) that this app's one row has neither of, and `AgoIcons` has no chevron at all. That is a
  separate promise about a separate control, and it is worth filing when Ещё has more than one row to
  draw.
- The tenant card the mockup puts at the top of the Ещё screen. It needs a tenant display name, a role
  and a site count that nothing in this app currently holds.

## Done when

- [x] One composable draws every in-screen section label (`SectionLabel`, `ui/components/`);
      `MoreScreen` no longer has its own copy.
- [x] Settings' three headings render as small, heavy, letterspaced, uppercase, faint-ink labels —
      not violet.
- [x] The strings in `strings.xml` are unchanged and still sentence case.
- [x] Checked in both light and dark: `--ink-faint` inverts (`Color.kt:27`, `:35`) and a label that is
      quiet in one theme must still be legible in the other.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.

Confirmed live on the real device (`F6VCHEZDAMRCPNJZ`): «ТЕМА» / «О ПРИЛОЖЕНИИ» render small, heavy,
letterspaced, uppercase, faint-ink in light mode and stay legible (not invisible, not full-white)
in dark.
