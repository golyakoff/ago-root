# 26-41 · The composer is a Material `TextField`, not the mockup's pill

- **Stage**: 26
- **Status**: done — merged as [ago-android#47](https://github.com/golyakoff/ago-android/pull/47)
- **Found**: 2026-09-23, reading the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) against `ago-android` `main` at `ad2859b`.

## Found

`26-23` rebuilt the composer's two *buttons* — the paperclip and the send button — against the
mockup's own vectors, and left the field between them alone. The field is the largest thing on that
row and it is the one part that does not match.

The mockup draws a bar with a hairline above it, and inside it a short, fully-rounded, sunken field:

```css
.composer{
  flex:0 0 auto; display:flex; align-items:center; gap:9px; padding:9px 12px;
  border-top:1px solid var(--line); background:var(--raised);
}
.field{
  flex:1; height:40px; border-radius:20px; background:var(--sunken); display:flex; align-items:center;
  padding:0 14px; font-size:13.5px; color:var(--ink-faint);
}
```

and its placeholder reads `Сообщение…`:

```html
<div class="composer">
  <div class="iconbtn"><svg class="i"><use href="#i-clip"/></svg></div>
  <div class="field">Сообщение…</div>
  <div class="iconbtn tinted"><svg class="i"><use href="#i-send"/></svg></div>
</div>
```

The app draws Material 3's default filled `TextField`: 56dp tall, square-shouldered with 4dp top
corners only, and carrying the filled variant's own underline indicator — a horizontal rule under the
text that the mockup has nowhere. Against a 40dp pill it is a different control, not a variant of the
same one, and it is half again as tall on the screen where vertical space is scarcest.

## What is actually true today, confirmed against real code

- `app/src/main/kotlin/ago/chat/android/thread/ThreadScreen.kt:459-460` — the bar itself:

  ```kotlin
  Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
      Row(modifier = Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
  ```

  The **background is right** and should not be touched: `surfaceContainer` is bound to
  `AgoSurfaceRaisedLight`/`Dark` (`ui/theme/Theme.kt:63`, `:109`), which is `--raised`. What is
  missing is `border-top:1px solid var(--line)` — `--line` is `outlineVariant`
  (`Theme.kt:47`, `:100`). Without it the composer and the message list share an edge with nothing
  drawn on it. The padding is a uniform `8.dp` where the mockup asks for `9px` vertical and `12px`
  horizontal.

- `ThreadScreen.kt:473-479` — the field:

  ```kotlin
  TextField(
      value = draft,
      onValueChange = onDraftChanged,
      modifier = Modifier.weight(1f),
      placeholder = { Text(text = stringResource(R.string.thread_composer_placeholder)) },
      maxLines = 5,
  )
  ```

  No `shape`, no `colors`: Material 3's `TextFieldDefaults` supply `surfaceContainerHighest` behind it
  (which in this app's scheme is `AgoSurfaceLight`/`AgoSurfaceDark`, not `--sunken`), the
  top-rounded-only `ShapeDefaults.ExtraSmall`, a 56dp minimum height and the filled variant's indicator
  line.

- `ThreadScreen.kt:480` inserts `Spacer(modifier = Modifier.width(8.dp))` between the field and the
  send button, and nothing between the paperclip and the field — where the mockup's `gap:9px` applies
  evenly to both sides of the field.

- `app/src/main/res/values/strings.xml` — `thread_composer_placeholder` is
  `Напишите сообщение…`; the mockup's `.field` reads `Сообщение…`. Shorter, and the shorter one is
  what fits a 40dp pill beside two buttons on a 360dp-wide phone.

## Scope

One promise: **the composer row is the mockup's composer row.** All of it is the same `Composer`
composable and the same visual object; splitting the field from the bar it sits in would land a pill
inside a bar with the wrong padding and no edge, which is not a state worth having.

1. **The field becomes the mockup's `.field`** — `40dp` tall, fully rounded (`CircleShape`, which at
   40dp is the mockup's own `border-radius:20px`), filled with `surfaceVariant` (`--sunken`,
   `Theme.kt:41`/`:96`), with `14dp` of horizontal text padding and **no indicator line** in any state.
   `TextField` with an explicit `shape` and `TextFieldDefaults.colors(...)` setting all four indicator
   colours transparent is the ordinary way to get there; `BasicTextField` inside a `Surface` is the
   other. Either is fine — say which and why in the report. Whatever it becomes must keep what works
   today: `maxLines = 5` growth, and the draft round-trip `ThreadViewModel` owns.
2. **The bar gets its top edge and the mockup's padding** — a `1dp` `outlineVariant` divider above the
   row, `9dp` vertical / `12dp` horizontal padding, and an even `9dp` gap on both sides of the field
   (an `Arrangement.spacedBy`, not a lone `Spacer` on one side).
3. **The placeholder becomes «Сообщение…»**, the mockup's own word.

## Out of scope

- What the paperclip does when tapped. Still deliberately nothing — `ThreadScreen`'s own top-of-file
  doc comment, and attachments are a later item.
- The send button. `26-23` already made it the mockup's `.iconbtn.tinted`, correctly, and
  `FilledIconButton`'s own defaults are that description.
- The delivery ticks in the bubble above — `26-42`.

## Done when

- [x] The field is a 40dp sunken pill with no underline in any state — unfocused, focused, and with
      text in it.
- [x] The composer has a hairline above it and the mockup's padding and gaps.
- [x] The placeholder reads «Сообщение…».
- [x] Typing, growing to five lines, sending, and the draft surviving a rotation all still work.
- [x] Checked in both light and dark — `--sunken` inverts between them (`Color.kt:41`, `:46`) and a
      field that reads as sunken in one theme can read as raised in the other.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.
- [x] Checked against the mockup on a real device.

Confirmed live on the real device, both themes, plus a real send. Real CI (`BackContractDialogsTabTest`)
caught a genuine regression in the first draft — the placeholder was a `Text` sibling beside
`BasicTextField`, leaving two disconnected semantics nodes so `performTextInput` on the placeholder text
could not focus the field. Fixed by moving the placeholder into `BasicTextField`'s own `decorationBox`,
which also gives TalkBack one node instead of two for what is visually one control.
