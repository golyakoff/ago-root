# 26-65 · A message bubble never says who wrote it — the author is colour, side and corner only

- **Stage**: 26
- **Status**: done — merged as [ago-android#59](https://github.com/golyakoff/ago-android/pull/59)
- **Found**: 2026-09-23, reading `ThreadScreen.MessageBubble` against `ago-android` `main` at
  `b099282`.

## Found

`26-23` rebuilt the bubble carefully and made every author signal visual, on purpose: the side of the
screen, the fill colour, and which bottom corner carries the tail. Its own doc comment
(`ThreadScreen.kt:363-388`) is explicit that the old symmetric shape was a defect precisely because
"the only thing distinguishing them was which side of the screen they sat on".

All three signals are invisible to a screen reader, and two of the three are invisible to anyone who
cannot separate this brand violet from this warm grey. So a thread read aloud is an undifferentiated
run of sentences and clock times:

> "Здравствуйте! Оплата не прошла, а деньги списались. 09:38. Добрый день! Сейчас посмотрю по заказу.
> 09:39. Спасибо. 09:40."

Which of those the operator wrote is not recoverable. On a support thread, that is not a nicety — an
operator scanning back through a conversation by ear cannot tell what they already said.

## What is actually true today, confirmed against real code

- `MessageBubble` (`ThreadScreen.kt:390-422`). `isOperator` is computed at `:392` and used in exactly
  three places, all purely visual:
  - `horizontalArrangement = if (isOperator) Arrangement.End else Arrangement.Start` (`:395`)
  - `color = if (isOperator) …primary else …surfaceVariant` (`:402`)
  - `shape = bubbleShape(isOperator = isOperator)` (`:404`)
- The `Column` inside holds two `Text`s — the body and the clock time — with no semantics of their
  own (`:406-415`), so each bubble contributes two unlabelled nodes.
- There is no `semantics` block anywhere in `ThreadScreen.kt`. Contrast this with the same file's own
  composer, where `26-23` was careful in exactly the right way: the send button's visible label was
  replaced by an icon and the string was **kept as the accessible name**, with a comment saying why
  (`ThreadScreen.kt:481-492`: "a send button that a screen reader announces as 'button' and nothing
  else is worse than the text one it replaces"). That care did not reach the bubbles.
- `MessageDto.authorKind` carries more than two values — the code compares against the literal
  `"Operator"` (`:392`) and treats everything else as the visitor, which lumps a system message in
  with the visitor's own words. `26-42`'s own Out of scope already notes "a visitor's or system bubble
  renders no tick", so a third kind is real.
- The timestamp is rendered as `HH:mm` (`:449`), which TalkBack reads as digits — acceptable, but it
  is the second unlabelled fragment per bubble and belongs in the same fix.

## Scope

One promise: **a screen reader can tell who wrote each message.**

1. Each bubble becomes one accessibility node whose description names the author, then the body, then
   the time — `semantics(mergeDescendants = true)` with an explicit `contentDescription`, the same
   shape `26-64` applies to a list row.
2. **Three authors, not two.** The description distinguishes the operator, the visitor and a system
   message, rather than folding the third into the second the way the current `isOperator` boolean
   does. Whether the *visual* treatment also gains a third case is a separate question this item does
   not answer — but the spoken form must not claim a system notice came from the customer.
3. The author name comes from resources, and the time is spoken as a time.
4. The visual treatment is untouched. `26-23`'s fill, shape and alpha decisions are correct and this
   item adds nothing to the screen.

## Out of scope

- **A visible author label.** The mockup draws none, and adding one would undo `26-23`'s whole
  argument for the bubble's shape carrying that information.
- **Delivery ticks** — `26-42`, which will add another element to the same `.t` line and should carry
  its own description when it lands. Note the overlap in whichever report lands second.
- **The conversation list's rows** — `26-64`. Same technique, different screen, and either can land
  alone.
- **Colour contrast.** Checked while filing: `onPrimary` on `primary` is stated at 6.27:1 in light and
  measured over 4.5:1 in dark (`ui/theme/Theme.kt:18`, `:71-72`), and the timestamp's alpha is taken
  over the bubble's own content colour precisely so it stays readable on the solid fill
  (`ThreadScreen.kt:379-383`). There is no contrast defect here to file.

## Done when

- [x] With TalkBack on, each bubble is announced with its author, its text and its time, as one node —
      proven by `MessageBubbleSemanticsTest`, not by a real signed-in thread (see below).
- [x] A system message is not announced as the visitor's.
- [x] Nothing about the bubble's appearance changes.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.
- [~] Verified on a real device with TalkBack actually enabled, on a thread containing at least one
      message from each author kind — **partial**. TalkBack itself is not installed on the test
      device; `MessageBubbleSemanticsTest` renders `MessageBubble` directly with fixture data for each
      author kind and passes 5/5 on the real device, but a genuinely signed-in thread with real
      messages from all three authors was not reachable — the session's existing SSO expired
      mid-session. Recorded honestly rather than overclaimed.
