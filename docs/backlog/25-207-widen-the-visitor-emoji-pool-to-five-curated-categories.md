# 25-207 · Widen the visitor emoji pool to five curated categories

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-21, flagged during the Android mockup round 2 (`26-00`) while designing the
  visitor-avatar mockups: half of `VisitorEmojiDictionary.Creatures`
  (`ago-chat/src/Ago.Chat.Domain/VisitorEmojiDictionary.cs:44-46`) is animal *faces* (🐶🐱🐭🐹🐰🦊🐻
  🐼🐨🐯🦁🐮🐷🐸🐵) that read alike at small size - the exact "near-duplicate" failure mode
  `25-56`'s own decision 3 already named as the rule to avoid, just not fully achieved with only
  twenty members to draw from. The author's own instruction, given while reviewing the mockups:
  widen the pool and curate it by category, using Telegram's own top-level emoji-picker groups as the
  reference.

## What is actually true today, confirmed against real code

`VisitorEmojiDictionary` holds exactly two arrays, twenty members each - `Creatures` and `Foods` - and
`Visitor.AssignEmojiPair` (guarded against reassignment) draws one member from each, permanently, the
moment a visitor is first seen. `25-56`'s own decision 4 already accepts repeats across visitors as a
mnemonic, not a uniqueness guarantee, so 400 combinations was never claimed to be enough forever -
only enough to make a repeat "occasional rather than routine" for a small tenant. A backfill
migration (`Stage25AddVisitorEmojiPair`) already copied today's exact twenty-plus-twenty members into
a one-time SQL literal - **that migration is never edited**, regardless of what this item changes
(`db-migration` skill's own rule).

## Scope

- **Widen from two categories (`Creatures`, `Foods`) to five**, matching Telegram's own top-level
  groups, per the author's explicit list: животные и природа, еда и напитки, активности, путешествия
  и места, объекты (animals & nature, food & drink, activities, travel & places, objects).
- **Explicitly excluded from every category**: flags (political, and many read alike at small size),
  plain geometric shapes/symbols (nothing to remember), human and smiley faces, hands and fingers,
  families and people - and, carried over from `25-56`'s own existing rule, anything that reads as a
  near-duplicate of another member in its own category at a glance. When genuinely unsure whether a
  candidate glyph belongs, this item asks rather than guesses (the standing instruction from
  `feedback_avatar_emoji_curated_categories` memory).
- **The pair-from-two-different-categories rule stays** (`25-56` decision 2) - widening from two
  categories to five makes this cheaper to satisfy, not harder, since there are more valid
  cross-category pairs to draw from.
- **Twenty-five members per category** is the Android mockup's own working number (25 × 5 = 125 total
  members, giving on the order of 2,500 ordered cross-category pairs against today's 400) - confirm
  this count still satisfies `25-56`'s own "visually and semantically distinct, no near-duplicates"
  bar before locking it in; a smaller per-category count that still clears that bar is an acceptable
  outcome, a larger one only if the bar still holds at that size.
- **A domain-only change.** `VisitorEmojiDictionary`'s own shape (two named `IReadOnlyList<string>`
  properties) becomes five, or the shape changes to a named-category structure if that reads better -
  decide and justify. `VisitorEmojiPairGenerator` (Infrastructure) picks two different categories, then
  one member from each, replacing its current two-list logic.
- **No migration for existing visitors.** `Visitor.AssignEmojiPair`'s own permanence rule means
  nothing about an already-assigned visitor changes; only a newly-seen visitor is drawn from the wider
  pool. No backfill, no schema change - this is a pure code/data change deployed like any other.
- **Both clients get this for free.** `ago-console`'s `workspace/visitorEmoji.ts` and `ago-widget`
  (wherever it renders the pair, if anywhere) render whatever the server assigned - confirm neither
  client hardcodes the old twenty-member lists for validation or lookup in a way this change would
  break, and fix it in the same change if it does.

## Out of scope

- Anything about the Android app itself - the mockups only surfaced this, they do not consume it
  directly (the mobile app renders the same server-assigned pair the console does).
- Retroactively changing any already-assigned visitor's pair.
- The backfill migration `Stage25AddVisitorEmojiPair` - untouched, per the standing migration rule.

## Done when

- [ ] `VisitorEmojiDictionary` (or its replacement shape) holds five categories, each member checked
      against the "visually and semantically distinct, no near-duplicates, no faces/hands/flags/
      shapes/families" bar - a real per-member justification, not a copy-pasted emoji block.
- [ ] `VisitorEmojiPairGenerator` draws from two different categories, one member each, and a domain
      test proves both the cross-category rule and that every generated pair's members come from the
      new dictionary.
- [ ] An already-assigned visitor's pair is provably unchanged by this item (a test using a fixed,
      pre-existing assignment).
- [ ] Neither `ago-console` nor `ago-widget` needs a code change to keep rendering correctly - or, if
      one does, it is made in this same change and stated explicitly.
- [ ] `dotnet format`/`build`/`test` all green, full suite counts reported.
