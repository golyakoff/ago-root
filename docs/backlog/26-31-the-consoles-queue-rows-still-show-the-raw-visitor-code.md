# 26-31 · The console's queue rows still show the raw eight-character visitor code

- **Stage**: 26
- **Status**: done — merged as `ago-console#271`. Verified against real code: `ConversationList.tsx`
  no longer renders the short code in either queue section (both call `visitorQueueRowLabel`);
  `ConversationPage.tsx` still shows it deliberately (per this item's own recommendation); `.ago-
  visitor-shortcode` is kept because `ConversationPage.tsx` still uses it.
- **Found**: 2026-09-22, by the author, reviewing the Android conversation list against the mockup and
  then extending the same judgement to every surface that shows it: "Что лишнее в мокапе и надо убрать
  - восьмизначные коды диалога - на экране они лишние - 01a0c839. 1. И в мокапе 2. И в реальном
  приложении андроид 3. И в консоли".

## What is actually true today, confirmed against real code

`ago-console/src/workspace/ConversationList.tsx` renders, in **both** queue sections (assigned, lines
~108–113; waiting, lines ~180–185), the same three-part label inside one `Badge`:

```tsx
<VisitorAvatar emojiCreature={c.emojiCreature} emojiFood={c.emojiFood} />
{visitorLabel(c, strings.visitorEmojiNames)}
<span className="ago-visitor-shortcode">{c.visitorId.slice(0, 8)}</span>
```

`visitorLabel` (`src/workspace/visitorEmoji.ts`, `25-207`) already returns a real human label in every
case a pair exists — the visitor's own name if given, otherwise «Сова · Клубника». So the short code
adds nothing for any visitor created since `25-56`'s backfill; it is a second identity beside a
perfectly good first one.

The same `.slice(0, 8)` appears on `ConversationPage.tsx` (~line 736), the single-conversation view.

## Scope

One promise: **an operator scanning the console's queue reads names, not hex.**

Remove the short code from the queue rows in `ConversationList.tsx` — both sections. Keep the
surrounding `Badge`, the avatar and `visitorLabel` exactly as they are.

**Decide, and say which, for the two edge cases rather than leaving them to fall out:**

- A visitor with **neither** a name nor an emoji pair (a row predating `25-56`, or an in-flight
  write). `visitorLabel` returns `""` for that, so removing the code would leave the badge blank.
  That row needs *something*; the short code is the honest fallback, and keeping it only there is a
  smaller rule than keeping it everywhere.
- `ConversationPage.tsx`'s own copy. The conversation page is where an operator would actually need
  an id to quote in a support ticket or a log search, which is the opposite of the queue's "scan many
  rows fast" job. **Recommendation: leave it.** If the author wants it gone there too, that is a
  one-line follow-up, not a reason to widen this item now.

Check `ago-console`'s own `.ago-visitor-shortcode` CSS for whether it becomes dead after this, and
remove it if it does — a class nothing uses is a trap for the next reader.

### The mockup's own correction is tracked separately

The author's first sub-point was the mockup Artifact itself. Only the managing session can edit it;
that is not in this item's Done-when.

## Out of scope

- The Android row's own copy of the code — `26-30`.
- Anything else about the console's queue layout. The author's other notes were about the Android
  screen; porting the mockup's row to the console is not something he asked for and is not assumed
  here.

## Done when

- [x] Neither queue section renders `visitorId.slice(0, 8)` — both call the new `visitorQueueRowLabel`.
- [x] A visitor with no name and no emoji pair still renders something identifiable (the short code,
      kept as the documented fallback exactly there — see `visitorEmoji.ts`'s own comment on
      `visitorQueueRowLabel`).
- [x] `.ago-visitor-shortcode` kept — `ConversationPage.tsx` still uses it, confirmed by a real grep.
- [x] `npm run typecheck`, `npm run lint`, `npm test` and `npm run ux-gate` all green.
