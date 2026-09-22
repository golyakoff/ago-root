# 26-32 · The conversation list's top bar is still a debug bar

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-22, by the author, on his own phone, against the approved mockup. Two of his
  notes, both about the same two rows of chrome above the list:
  - "Что за строка сверху «01a07262 (*) Соединение: Подключено»? Давайте и на мокап и в
    андроид-приложение добавим зелёную|красную точку (маленький кружочек) - признак онлайн/оффлайн?
    что это за код - не понимаю, вроде не один из диалогов? какой-то ещё? наверное он тут не нужен.
    В общем - посыл такой - эта строка занимает ценное вертикальное место, хотя вся её информативность
    - это 1 бит - соединено или нет. Надо придумать как это нарисовать компактнее не занимая отдельной
    строки."
  - "«Выйти» - сейчас везде справа сверху - наверное должны быть три точки как на мокапе, там один из
    пунктов «Выйти»"

## Why these are one item and not two

They are two complaints, but one promise and one piece of code: both land inside the single
`TopAppBar(...)` block in `ConversationListScreen.kt` (lines ~159–180) and the `Column` wrapped around
it. Two separate items would edit the same twenty lines and conflict with each other on the one thing
`background-worker-brief` judges non-interference by — files. One item, one rebuild of that header.

## What is actually true today, confirmed against real code

`ConversationListScreen`'s `topBar` is a `Column` of **two** rows:

1. A `TopAppBar` whose only action is `TextButton(onClick = onSignOut) { Text(action_sign_out) }` —
   the literal «Выйти» the author sees. The mockup's header has a search icon and a vertical
   three-dot overflow in that slot, and no sign-out text anywhere.
2. A second, full-width `Row` — this is the mystery line — containing
   `IdentifierText(id = activeSiteId)` followed by `HubConnectionDebugRow(state = ...)`.

So the two answers the author was missing:

- **`01a07262` is the active site's id**, not a conversation's. It is `activeSiteId`, put on screen by
  `26-14` for a reason its own doc comment states: an operator holding seats on several sites can see
  which one this queue is. That is a real need, but it is not a need that justifies a permanent line,
  and `26-17`'s Settings screen now shows and switches the active site properly — so this row is a
  leftover, not the mechanism.
- **The connection row was always explicitly a debug row.** `HubConnectionDebugRow`'s own doc comment
  says so: "`26-13`'s own 'a minimal connection-state surface' — a debug row, not a designed status
  indicator... A real one is a later item's job." This is that item.

It already draws the dot the author is asking for — an 8dp `CircleShape` `Box` coloured `primary` /
`tertiary` / `error` by state — with the words bolted beside it. The dot is not new work; removing the
words and the row around it is.

## Scope

One promise: **the conversation list's header is the mockup's header — one row, with the connection
state costing no vertical space at all.**

1. **The debug row goes**, both halves: the site id and the `Соединение: …` text.
2. **The connection state becomes a compact indicator inside the existing top bar.** The author's own
   proposal is a small green/red dot; take it, and decide where it sits — beside the «Диалоги» title
   is the natural place. Four states exist (`Disconnected`, `Connecting`, `Connected`, `Reconnecting`),
   not two: keep the existing three-colour mapping rather than flattening it to green/red and losing
   the "trying" state. A dot alone is invisible to a screen reader, so it needs a real
   `contentDescription` carrying the current state in words — the strings already exist
   (`hub_connection_*` in `strings.xml`), so keep them for that purpose rather than deleting them.
   Consider showing nothing at all in the `Connected` steady state, so the indicator reads as "something
   is wrong" rather than as decoration — decide, and say which you chose and why.
3. **«Выйти» moves into an overflow menu.** A `⋮` icon action opening a `DropdownMenu` with «Выйти» in
   it, drawn as a real vector icon from `AgoIcons` (the mockup's own sprite is the source — `26-23`
   transcribed the rest of it there already; `i-dots` is in that item's own icon table). Not
   `Icons.Default.MoreVert`, for the same reason `26-23` did not use Material's defaults: the mockup's
   icons are one stroke-drawn set.
4. **`HubConnectionDebugRow` itself.** Check whether anything else still calls it (`SignInScreens.kt`
   threads a `hubConnectionState` through) before deleting it. If it survives only for the pre-session
   screens, leave it there and stop rendering it here; if nothing uses it, delete it rather than leave
   a dead composable named "Debug" in the tree.

5. **The thread screen's identical copy of that row.** Added to this item's scope after the check in
   point 4 found it: `ThreadScreen.kt` draws the very same `HubConnectionDebugRow` on its own line
   under its own app bar. It is the same defect, the same composable and the same one-bit-per-line
   complaint — and on the thread screen a line taken from the top is a line taken from the
   conversation, so it costs more there, not less. Fixing one and leaving the other would be half a
   fix of one thing, which `finish-an-item`'s own reading of rule 15 does not make into two tickets.
   Only the connection indicator moves there; the thread has no «Выйти» and gets no overflow menu.

### What this item deliberately does not add

The mockup's header also has a **search** icon, and below it a segmented control with counts and a
filter chip row. There is no search, no filtering and no tab counts in this app; drawing the
affordances without them would be worse than not drawing them. Each needs its own item when the
feature behind it exists.

### The mockup's own correction is tracked separately

The author asked for the connection dot to be added to the mockup Artifact too. Only the managing
session can edit it; that is not in this item's Done-when.

## Out of scope

- The blank band above the top bar — `26-28`.
- The rows below it — `26-30`.

## Done when

- [ ] The conversation list has exactly one row of chrome above the tab control, and the thread
      screen has exactly one above its transcript.
- [ ] The active site id no longer appears on this screen (it is still visible and switchable in
      Настройки).
- [ ] Connection state is shown on both screens without a line of its own, distinguishing all four
      states, with a spoken `contentDescription` for a screen reader.
- [ ] «Выйти» is reachable only through a `⋮` overflow menu drawn from `AgoIcons`.
- [ ] `HubConnectionDebugRow` is either still genuinely used elsewhere or deleted — not orphaned.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green, and any test that found sign-out by its
      old top-bar button is updated to drive the menu.
- [ ] Checked on a real device or emulator against the mockup.
