# 26-64 · A conversation row reads to TalkBack as five disconnected fragments

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, reading `ConversationListScreen` and `VisitorAvatar` for semantics against
  `ago-android` `main` at `b099282`.

## Found

A row on the busiest screen in the app is built from five separate `Text`/`Box` nodes, none of which
carries any semantics of its own. TalkBack walks them one at a time, and what it says is roughly:

> "Fox face. Tangerine." … "Лиса · Апельсин" … "2" … "4 ч" … "Оплата не прошла" … "Двойное нажатие
> для активации"

Four problems, and only the last is a matter of taste:

1. **The avatar is read at all.** It is a duplicate — the emoji pair's own name is already spoken by
   the identity line right after it — and it is read as *emoji glyph names*, in the TTS engine's
   language, which is not necessarily Russian. It should be silent.
2. **The unread count is a bare numeral.** "2" between a name and a time means nothing.
3. **«4 ч» is unexplained.** It is the conversation's age; the same short form appears again on the
   snippet line meaning something else entirely (the last message's time). Sighted readers tell them
   apart by weight and position; a listener gets two identical-sounding fragments.
4. **The row is not one thing.** A list row that is one tap target should be one accessibility node
   saying one sentence, not five nodes the user has to assemble.

The app does know how to do this. `HubConnectionDot`
(`ui/components/HubConnectionDot.kt:66-74`) is a bare 8dp coloured `Box` that carries a full
`contentDescription`, and its doc comment states the rule outright: "a coloured circle with no text is
invisible to a screen reader and meaningless to anyone who cannot separate this green from this red."
The row never got the same treatment.

## What is actually true today, confirmed against real code

- `ConversationRow` (`ConversationListScreen.kt:360-400`) composes `VisitorAvatar`, an identity line,
  an optional snippet line, an optional pill row and a trailing slot. There is no `semantics {}`, no
  `mergeDescendants`, and no `clearAndSetSemantics` anywhere in the file.
- `VisitorAvatar` (`ui/components/VisitorAvatar.kt:41-75`) draws two `Text`s holding raw emoji
  characters, with no description and no suppression.
- `UnreadBadge` (`ConversationListScreen.kt:549-573`) renders `count.toString()` and nothing else.
- `shortElapsedText` (`:671-687`) resolves «N мин»/«N ч»/«N д» with no unit word and no context, and
  is called from two lines meaning two different things (`:458` — age since creation; `:504` — the
  last message's time).
- The tap target: `MineRow` (`:330-340`) applies `Modifier.clickable(onClick = onClick)` with no
  `onClickLabel` and no `role`.
- «Ожидают» rows additionally hold a real `Button` inside the row
  (`:618-627`), which must stay its own focusable node — merging it into the row would make the claim
  action unreachable.

## Scope

One promise: **a conversation row reads as one sentence that says who, how old, how many unread, and
what was last said.**

1. **The row becomes one accessibility node** with a composed `contentDescription`, built from the
   same fields it draws — the identity, the age, the unread count *named as unread*, and the snippet.
   Compose's `semantics(mergeDescendants = true)` with an explicit description is the ordinary shape;
   on «Ожидают», the claim `Button` stays a separate node outside that merge.
2. **The avatar is excluded** — `clearAndSetSemantics {}` on `VisitorAvatar`, or its exclusion from
   the merge. It is decorative here by construction: the same pair is already spoken as a name.
3. **A tap label.** `clickable(onClickLabel = …)` so the action is announced as "открыть диалог"
   rather than "активировать".
4. **The two elapsed values stop being ambiguous** in the spoken form. They can stay identical
   visually — `26-30` chose that deliberately and it is right — but the description has to say which
   is which.
5. The string is assembled in one place from resources, never by concatenating what happens to be on
   screen with spaces — the description has to survive a row with no name, no snippet and no unread
   count without producing stray separators, the identical rule
   `visitorDisplayPrefixParts` already enforces for the visible text.

## Out of scope

- **The bottom bar's own unread badge.** `26-46` part 4 already owns that description, and explicitly
  reserves the row badge as fallout "if it is genuinely the same fix". It is not quite: this item is
  about the row as a whole and would subsume a badge-only description, so whichever lands second
  should check rather than assume.
- **The thread screen's bubbles** — `26-65`.
- **Settings' radio rows** — `26-66`.
- **Contrast and touch targets.** Both were checked in filing this batch and are in fact fine: the
  palette's own pairs carry measured ratios (`ui/theme/Theme.kt:18`, `:22`, `:44`), and every
  interactive control in the row is a Material component at its default minimum size. Nothing to fix,
  and nothing is being filed to look busy.

## Done when

- [ ] With TalkBack on, swiping through the conversation list speaks one coherent sentence per row.
- [ ] The emoji avatar is not spoken.
- [ ] The unread count is spoken as a count of unread messages, not as a bare number.
- [ ] The two elapsed values are distinguishable when spoken.
- [ ] On «Ожидают», the claim button is still reachable as its own focusable element.
- [ ] A row with no name, no snippet and no unread count reads cleanly, with no stray punctuation.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
- [ ] Verified on a real device with TalkBack actually enabled — not only by a semantics assertion in
      a Compose test.
