# 25-207 · One visitor emoji, drawn from five curated categories

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-21, flagged during the Android mockup round 2 (`26-00`) while designing the
  visitor-avatar mockups: half of `VisitorEmojiDictionary.Creatures`
  (`ago-chat/src/Ago.Chat.Domain/VisitorEmojiDictionary.cs:44-46`) is animal *faces* (🐶🐱🐭🐹🐰🦊🐻
  🐼🐨🐯🦁🐮🐷🐸🐵) that read alike at small size - the exact "near-duplicate" failure mode
  `25-56`'s own decision 3 already named as the rule to avoid.
- **Revised 2026-09-21**, same day: the author's own correction, after seeing the round-2 mockups
  render a two-emoji pair - "мы ещё разговаривали о том, чтобы перейти на 1 иконку эмодзи, но
  расширить сам набор иконок" (we already talked about moving to **one** emoji icon, and widening the
  icon set itself). The round-2 mockup worker had gone the other way - drawing a *pair* because that
  is what `25-56` shipped - which was a reasonable read of the code as it stands today, and is exactly
  what this item now changes. **This item's scope below is single-emoji, not pair-widening** -
  superseding this file's own first version, written before the correction.

## What is actually true today, confirmed against real code

`Visitor` (`ago-chat/src/Ago.Chat.Domain/Visitor.cs`) holds two nullable columns, `EmojiCreature` and
`EmojiFood`, set together and once by `AssignEmojiPair` (guarded against reassignment - see that
method's own remarks for why the invariant lives there). `VisitorEmojiDictionary` holds the two
twenty-member lists they are drawn from. A backfill migration (`Stage25AddVisitorEmojiPair`) already
copied today's exact lists into a one-time SQL literal - **that migration is never edited**, whatever
this item changes (`db-migration` skill's own rule), and neither is any already-assigned visitor's
own pair.

## Scope

- **One emoji per visitor, not two.** A new nullable column, `Visitor.Emoji`, additive per this
  project's own late-field convention (`api-design.md`'s "every late field is `T? Foo = null`,
  optional and absent for a session/row that predates it" - the identical shape `EmojiCreature`/
  `EmojiFood` themselves already are). `EmojiCreature`/`EmojiFood` are **not removed and not
  backfilled** - an already-assigned visitor keeps rendering exactly the pair it always has, forever;
  only a visitor first seen after this change gets `Emoji` populated instead. State this trade-off
  plainly rather than silently: the product will show two different visitor-identity shapes side by
  side (old visitors as a pair, new visitors as one icon) for as long as any pre-change visitor stays
  open, which for this product's own conversation lifetimes is not long.
- **`AssignEmojiPair` is replaced by `AssignEmoji(string emoji)`**, called once, guarded against
  reassignment the identical way. `VisitorEmojiPairGenerator` (Infrastructure) becomes a single-pick:
  choose one category, then one member of it - no cross-category pairing logic remains to maintain.
- **Widen the pool to five categories**, matching Telegram's own top-level groups, per the author's
  own list: животные и природа, еда и напитки, активности, путешествия и места, объекты (animals &
  nature, food & drink, activities, travel & places, objects). `VisitorEmojiDictionary`'s own shape
  becomes five named lists (or a category-keyed structure, if that reads better - decide and justify).
- **Explicitly excluded from every category**: flags (political, and many read alike at small size),
  plain geometric shapes/symbols (nothing to remember), human and smiley faces, hands and fingers,
  families and people - and, carried over from `25-56`'s own existing rule, anything that reads as a
  near-duplicate of another member in its own category at a glance. When genuinely unsure whether a
  candidate glyph belongs, this item asks rather than guesses (the standing instruction from
  `feedback_avatar_emoji_curated_categories` memory).
- **Pool size**: with no pairing to multiply against, "enough that a repeat is occasional, not
  routine" (`25-56` decision 4's own bar) applies to the flat pool size directly - name the real
  member count chosen per category and why it clears that bar; do not simply carry over the round-2
  mockup's own 25-per-category number, which was sized for a *pair's* combinatorics, not a single
  draw's.
- **Both clients get this for free.** `ago-console`'s `workspace/visitorEmoji.ts` and `ago-widget`
  (wherever either renders a visitor's identity) need to render `Emoji` when present and the existing
  pair when it is not - a real, small client-side change (not "for free" the way the previous version
  of this item assumed pairing would stay), stated explicitly here since it touches both.
- **Android mockups and docs get the correction too** - `ago-android/docs/plan.md`'s own emoji
  section and the mockup Artifact's avatar treatment currently show the round-2 worker's *pair*
  correction; both revert to one emoji per visitor, still drawn from the widened five-category pool.

## Out of scope

- Retroactively changing any already-assigned visitor's pair - never touched, ever.
- The backfill migration `Stage25AddVisitorEmojiPair` - untouched, per the standing migration rule.
- Actually removing `EmojiCreature`/`EmojiFood` from the schema - they stay, serving every
  already-assigned visitor for the rest of that visitor's life.

## Done when

- [ ] `Visitor.Emoji` exists as a new, additive, nullable column via a real EF migration; a newly
      seen visitor gets it populated, an already-assigned visitor's `EmojiCreature`/`EmojiFood` are
      provably untouched by this change (a test using a fixed, pre-existing assignment).
- [ ] `VisitorEmojiDictionary` holds five categories, each member checked against the curation bar
      above - a real per-member justification, not a copy-pasted emoji block - with a stated,
      justified pool size per category.
- [ ] `VisitorEmojiPairGenerator`'s replacement draws one category then one member, and a domain test
      proves every generated value comes from the new dictionary.
- [ ] `ago-console` and `ago-widget` render `Emoji` when present and fall back to the existing pair
      when it is not - both paths covered by a real test, not just the new one.
- [ ] `ago-android/docs/plan.md` and the mockup Artifact both show one emoji per visitor, from the
      widened pool - the round-2 pair correction reverted.
- [ ] `dotnet format`/`build`/`test` all green in `ago-chat`, full suite counts reported; `ago-console`/
      `ago-widget` each green on their own real command sets.
