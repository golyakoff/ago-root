# 26-30 · The conversation-list row still isn't the mockup's row

- **Stage**: 26
- **Status**: blocked on `26-29` for two of its five parts (the open question is now resolved — see
  below)
- **Found**: 2026-09-22, by the author, on his own phone, against the approved mockup Artifact
  ("AGO Chat для Android"). Four of his notes are about this one row:
  - "Не хватает имён Лиса (точка) Апельсин для тех, кто ещё не представился (смотри логику
    образования имён уже готовую в консоли)"
  - "Не хватает обрезанной последней строчки диалога второй строкой (под именем)"
  - "Всякие бейджики «Новое» и другие должны лечь третьей строкой."
  - "Лишнее слово «открыт» + нужно использовать короткие сокращения для времени: не «Открыт 4 часа» а
    «4 ч». не «Открыт 20 минут», а «20 мин»."
  - and, about the code, "восьмизначные коды диалога - на экране они лишние - 01a0c839".

## This is partly finishing `26-23`, not a fresh defect — say so plainly

`26-23` rebuilt this row and its own report **named three of these gaps itself**, as deliberate
omissions rather than oversights. `ConversationRow`'s doc comment in
`app/src/main/kotlin/ago/chat/android/conversations/ConversationListScreen.kt` says so in the code:
the snippet, the channel/tag pills and the emoji-derived name all had no field behind them, and that
item was presentation-only and "may not invent data". That was the right call. This item is what
picks those up, and it should not be written up as if `26-23` missed them.

**One of that item's three reasons was wrong, though, and this item corrects it.** `26-23` wrote that
an emoji-derived name has no precedent, "`visitorDisplayPrefixParts` has no such derivation and
neither does the console it mirrors". The console **does** have it, and has since `25-207`:
`ago-console/src/i18n/visitorEmojiNames.ts` maps all 40 glyphs of
`Ago.Chat.Domain.VisitorEmojiDictionary` to localized names, and
`ago-console/src/workspace/visitorEmoji.ts`'s `visitorFallbackLabel`/`visitorLabel` compose
"Сова · Клубника" for a nameless visitor. That is precisely the logic the author points at. So the
name fallback needs **no backend change at all** — only a port.

## What is actually true today, confirmed against real code

- `ConversationRowUi` (`conversations/ConversationListUiState.kt`) carries `conversationId`,
  `visitorId`, `emojiCreature`, `emojiFood`, `visitorName`, `createdAt`, `unreadCount`,
  `isNewlyAssigned`, `isClaiming`, `claimError`, `hasAttachmentUploadGrant`. No snippet, no
  last-message time, no channel, no tags.
- `ConversationRowIdentityLine` renders `parts.visitorName` when present and then **always** an
  `IdentifierText(parts.visitorId)` — the short code. For a nameless visitor (most visitors) the code
  is the entire line, which is what the author is seeing.
- There is no second line. The pill row (`isNewlyAssigned` → «Новое») is therefore drawn *directly*
  under the name line, occupying what the mockup uses for the snippet. The badges are not on the wrong
  line by choice; there is simply no line for them to be third of.
- `elapsedText` composes `stringResource(prefixRes)` + a plural — «Открыт 4 часа» / «Ждёт 20 минут» —
  from `R.string.conversation_list_opened_prefix`, `conversation_list_waiting_since_prefix` and the
  three `conversation_list_elapsed_*` plurals in `app/src/main/res/values/strings.xml` (the app has one
  locale; there is no `values-ru`).
- **The unread badge is not missing.** `MineRow` renders `UnreadBadge` whenever `row.unreadCount > 0`,
  and it is a real circular brand-filled badge (`26-23` built it). The author's screenshot shows none
  because `operatorUnreadCount` was zero on every row in that state — the rows carried «Новое»
  (assigned-this-session, not yet opened), which is a different signal. Nothing to fix here; recorded
  so nobody "fixes" a badge that works.

## Scope

One promise: **the conversation-list row shows what the mockup's row shows, laid out the way the
mockup lays it out.** Five parts, one row, one promise — they are deliberately not split, because
every one of them changes the same layout of the same composable and any two of them landing
separately would leave the row half-rebuilt.

1. **A name for a nameless visitor.** Port the console's `25-207` derivation into `:core:domain`:
   the 40-glyph table and the "`visitorName` if present, else `{creature} · {food}`, else nothing"
   rule. Copy every glyph key **byte-for-byte** out of
   `ago-chat/src/Ago.Chat.Domain/VisitorEmojiDictionary.cs` — never retyped from an emoji picker —
   for the `U+FE0F` variation-selector reason `visitorEmojiNames.ts`'s own header spells out, and
   carry a completeness test the way that file's own `visitorEmojiNames.test.ts` does. Russian only;
   the app has one locale, and the table should be shaped so a second locale is additive rather than
   a rewrite. `visitorDisplayPrefixParts` is the right home for the composition rule, so the thread
   screen's app-bar title gets it too.
2. **The snippet line.** The mockup's `.rsnip`: one line, ellipsised, under the name, now also
   carrying the last-message timestamp beside the snippet text (see "The time question" below) — both
   from `26-29`'s new fields. A row with no messages simply has no snippet line at all — not an empty
   line, not a placeholder, and therefore no orphaned timestamp either.
3. **The badge line.** With a snippet line present, the pill row becomes the third line, which is what
   the author asked for and what the mockup already draws. Only the pills that have a real field behind
   them: «Новое» today. Channel/tag pills stay out — Stage 14, no data.
4. **The short elapsed format, with no prefix, for both timestamps.** «4 ч», «20 мин», «2 д» — the
   word «Открыт»/«Ждёт» goes, on the name line's own age-since-creation *and* on the new snippet
   line's last-message time — one shared formatting function, not two. Keep the existing
   rounding-towards-the-past rule; only the rendering changes. The two tabs no longer differ in their
   name-line prefix, so check whether the two prefix strings and the `elapsedPrefixRes` parameter can
   go entirely.
5. **The raw short code goes.** Drop `IdentifierText` from this row. With part 1 landed, every visitor
   has *some* human label, so the code is no longer carrying any load here. Note that the code is
   still the right thing elsewhere (the thread screen, anywhere an operator has to dictate or match an
   id) — this removes one call site, not `IdentifierText`.

### The time question, resolved by the author — both instants render, on different lines

Part 4 used to be blocked on **which** instant the row shows. The author's own resolution (recorded in
full in `26-29`) dissolves the choice instead of picking a side: **show both**, each beside the text it
describes, rather than one timestamp doing double duty.

- **Name line** (line 1): the conversation's own age-since-creation — exactly the `elapsedText`
  rendering that exists today, format corrected per part 4 below (`«4 ч»`/`«20 мин»`/`«2 д»`, no
  prefix). Rendered in the **name line's own font weight** (bold/prominent) — the author's own framing:
  this instant is "more active" because it describes the whole dialog. Sort order is **unchanged** for
  both tabs — this is the same value `elapsedText(row.createdAt, ...)` already reads, so «Ожидают»'s
  own oldest-first sort needs no change and has no collision to worry about.
- **Snippet line** (line 2, new): the last-message instant from `26-29`'s new field, in the same short
  format, set beside the snippet text in the **snippet line's own (lighter) weight** — so the
  timestamp reads as describing those specific words, not the dialog as a whole. Absent whenever the
  snippet itself is absent (a conversation with no messages) — never a lone timestamp with nothing to
  attach to.

No per-tab branching of any kind is needed: both instants render unconditionally, on both tabs,
wherever their backing data is present. This replaces the item's own earlier "pick one instant per
tab" framing entirely.

### The mockup's own corrections are tracked separately

The author also asked for the eight-character codes to come out of the mockup Artifact itself, and for
the connection dot to be added to it. Only the managing session can edit that Artifact; those changes
are **not** in this item's Done-when and are tracked outside it.

## Out of scope

- The backend fields themselves — `26-29`.
- The top bar — `26-32`. The blank band above it — `26-28`.
- The console's own copy of the short code — `26-31`.
- Channel/tag pills, the chip filter row and the tab counts the mockup draws. No data behind any of
  them today; each needs its own item when there is.

## Done when

- [ ] A nameless visitor with an emoji pair renders as «Лиса · Апельсин» wherever the row (and the
      thread app bar) previously rendered a bare code; a named visitor is provably unchanged.
- [ ] The glyph table is byte-identical to `VisitorEmojiDictionary.cs` and a test proves all 40
      glyphs resolve.
- [ ] The row draws a single-line ellipsised snippet under the name when `26-29`'s field is present,
      and no snippet line at all when it is absent.
- [ ] «Новое» sits on its own line below the snippet.
- [ ] Elapsed time renders as «4 ч» / «20 мин» / «2 д» with no «Открыт»/«Ждёт» prefix, on both the
      name line's own age-since-creation and the snippet line's own last-message time.
- [ ] Both timestamps render on both tabs, unconditionally, each in its own line's font weight (name
      line: bold; snippet line: regular) — no per-tab branching of which instant to show, and sort
      order is unchanged on both tabs.
- [ ] No eight-character code appears on the conversation-list row.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green; tests that asserted the old row structure
      are updated to the new one, never deleted to go green.
- [ ] Checked against the mockup on a real device or emulator, not only in a preview.
