# 26-23 · The conversation list, thread screen and bottom nav don't match the approved mockup

- **Stage**: 26
- **Status**: done — merged. Verified against real code: `BottomDestination.emoji()` gone, bottom nav
  uses real `AgoIcons.Chat/Bookings/Team/Analytics/More` vectors; new `VisitorAvatar.kt`; thread screen
  uses `AgoIcons.Back` (no more literal `"←"`) and a real `bubbleShape(isOperator)` (no more symmetric
  14dp on both sides).
- **Found**: 2026-09-22, by the author, comparing the real `26-14`/`26-15`/`26-16` screens (installed
  from the latest release) against the approved mockup Artifact ("AGO Chat для Android",
  `https://claude.ai/code/artifact/8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) that `26-14`/`26-15`/`26-16`
  were themselves built against. In the author's own words: "список диалогов выглядит не так, диалог
  внутри выглядит не так, кнопки в подвале сделаны через эмодзи, похоже, а не через svg google icons."

## What is actually true today, confirmed against real code

- `BottomDestination.emoji()` (`shell/AppShellScreen.kt`) returns a plain-text emoji per destination
  (`"💬" "📅" "👥" "📊" "☰"`), rendered via `Text()` inside `NavigationBarItem`'s `icon` slot — no
  vector icon anywhere in the bottom bar. The file's own doc comment on `emoji()` cites `ThreadScreen`'s
  `"←"` as its precedent for "this app's own established convention" — both are the same gap.
- `VisitorDisplayPrefix` (`ui/components/VisitorDisplayPrefix.kt`) renders the emoji creature and food
  as one inline string, side by side (`"${pair.creature}${pair.food}"`) — exactly the "old squeezed-pair
  glyph" the mockup's own CSS comment (`.av.pair`, line ~222 of the saved mockup HTML) records as
  rejected, in favour of a circular avatar with the creature centred and the food floating as a small
  corner badge with no background of its own.
- `ConversationListScreen`'s `MineRow`/`WaitingRow` lay out as a plain `Row`: no avatar circle, no
  status pills (new/channel/tag), no unread-count badge in the mockup's shape — only a name/time line
  and one elapsed-time line.
- `ThreadScreen`'s `TopAppBar` back control is a literal `Text("←")`; message bubbles use a symmetric
  `RoundedCornerShape(14.dp)` on both sides, filled with `MaterialTheme.colorScheme.primaryContainer`
  (operator) / `surfaceVariant` (visitor) — not the mockup's asymmetric bubble (16dp corners, 5dp on the
  "tail" corner) in solid `primary` (operator, white text) / `sunken` (visitor). The composer's attach
  control is a literal `Text("📎")`.

**One reassuring finding, worth stating so the worker doesn't second-guess it**: the app's actual
`MaterialTheme` colour tokens (`ui/theme/Color.kt`, `Theme.kt`) are already a byte-for-byte
transcription of the same `tokens.css` the mockup itself renders from — confirmed directly,
`AgoBrandLight = 0xFF4B3AFF` against the mockup's own `--brand:#4b3aff`, and the same match holds for
every other token checked. **This item is a rendering/composition fix, not a colour-system one.** Every
colour the mockup calls for already has a `MaterialTheme.colorScheme` role; nothing here should invent
a new `Color(0x...)` literal outside `ui/theme/Color.kt`.

## Scope

One promise: **the already-shipped conversation-list, thread, and bottom-nav screens visually match
the mockup they were supposed to be built from.** Four places, one promise:

1. **Bottom nav icons** — replace `BottomDestination.emoji()`'s `Text()` rendering with real vector
   icons (`Icon()`, Compose `ImageVector`s or vector drawables), using the mockup's own path data,
   not redrawn approximations. Material 3's default `NavigationBarItem` selected-state indicator
   (`primaryContainer` pill behind the icon) already matches the mockup's `.ind`/`.on` treatment —
   confirm this rather than reimplementing it.
2. **Conversation-list avatar** — rebuild the avatar so the creature emoji renders centred inside a
   40dp circular `primaryContainer`-filled background, with the food emoji as a small corner badge
   (no background of its own), replacing `VisitorDisplayPrefix`'s current inline pair for this call
   site. `VisitorDisplayPrefix` itself may still be the right building block for the thread app-bar's
   plain-text title (which has no avatar) — decide whether it needs a variant or a new composable.
3. **Conversation-list row layout** — rebuild `MineRow`/`WaitingRow` to show: the avatar, a name+code
   line with elapsed time trailing, a snippet line below, a wrapping row of status pills, and the
   unread-count badge as a small circular badge at the row's trailing edge.
4. **Thread screen** — replace the `"←"` text back button and the composer's `"📎"` text glyph with
   real vector icons; give message bubbles the mockup's asymmetric shape and correct fill/text colours
   (operator: solid `primary`, white/`onPrimary` text; visitor: `surfaceVariant`/sunken fill, `onSurface`
   text).

Use the mockup's real SVG path data (below) as the source for every new icon.

### Icon source data (from the mockup's own `<symbol>` sprite, `viewBox="0 0 24 24"`)

```
i-chat  (Диалоги):   <path d="M21 12a8 8 0 0 1-8 8H7l-4 3 1-4.5A8 8 0 1 1 21 12z"/>
i-cal   (Записи):    <rect x="3" y="5" width="18" height="16" rx="2.5"/><path d="M3 10h18M8 3v4M16 3v4"/>
i-team  (Команда):   <circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.2 2.7-5.2 6-5.2s6 2 6 5.2"/>
                     <path d="M16 5.2A3.2 3.2 0 0 1 16 14"/><path d="M18 20c0-2.4-.8-4-2-4.8"/>
i-chart (Аналитика): <path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>
i-dots  (Ещё):       <circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/>
i-back:              <path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/>
i-clip:              <path d="M20 11l-8.5 8.5a4.5 4.5 0 0 1-6.4-6.4l9-9a3 3 0 0 1 4.3 4.3l-9 9a1.5 1.5 0 0 1-2.1-2.1l8-8"/>
i-send:              <path d="M4 12l16-8-6 16-2.5-6.5L4 12z"/>
```

All stroke-only (`fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round;
stroke-linejoin:round`), never filled shapes — the mockup's whole icon set is drawn this way.

## Out of scope

- The attachment picker's real behaviour, the visitor-context sheet, and any other functional change —
  `26-15`'s own scope already carries those forward; this item is presentation only.
- Any screen not named above (Settings, More, placeholders) — not part of the mockup complaint that
  raised this item.

## Done when

- [x] Bottom nav renders five real vector icons — confirmed by grep (`AgoIcons.Chat/Bookings/Team/
      Analytics/More`, no more `Text()`-rendered emoji).
- [x] The conversation-list avatar rebuilt (`VisitorAvatar.kt`, new file).
- [x] Conversation-list rows rebuilt to the mockup's layout.
- [x] Thread screen's back button is `AgoIcons.Back` (no more literal `"←"`); message bubbles use a
      real `bubbleShape(isOperator)` (no more symmetric shape on both sides).
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.
- [x] Existing tests updated to match the new structure.
