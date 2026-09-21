# 25-207 · Visitor avatar becomes a badge, with a localized name instead of a bare pair

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-21, flagged during the Android mockup round 2 (`26-00`) while designing the
  visitor-avatar mockups, then revised twice the same day through a live design conversation with the
  author. **This is the third and final version of this item's scope** - the two versions before it
  (widen to five categories with a cross-category pair; a single emoji in a new `Visitor.Emoji`
  column) are both superseded by what follows. Neither is this item's scope any more.

## What the conversation actually settled, in order

1. The visual complaint was never about the *mechanic* (two emoji, one memory aid) - it was that two
   same-size glyphs side by side reads as cluttered. **Resolution: a badge composition, not a pair
   side by side** - the creature emoji large and centered in the existing avatar circle (its own
   font-size **+15%**, the circle itself unchanged), the food emoji as a small badge overlapping the
   bottom-right edge with **no background circle of its own** - confirmed live, with three visual
   variants compared in an Artifact, before settling on this one.
2. **The emoji pool and category roles do not change.** `VisitorEmojiDictionary`'s existing two lists
   stay exactly as they are - `Creatures` for the large centered icon, `Foods` for the badge, fixed
   roles, not a cross-category pair from a widened five-category pool. The author's own words settling
   this: "мы остаёмся в прежнем сете. животные для первого эмодзи и еда и напитки для бейджа."
   **`Ago.Chat.Domain` is untouched by this item** - no new column, no schema change, no migration.
3. **A localized name reads better than a bare pair next to a hex code.** Today's console format
   (`visitorEmojiPrefix`/`visitorDisplayPrefix`, `ago-console/src/workspace/visitorEmoji.ts`) renders
   `{emoji}{emoji} {name-if-known} {shortcode}` - when no real name is known, that is two glyphs and a
   hex string, nothing a person reads as words. **Resolution: render each emoji's own name** (e.g.
   `Сова · Клубника`) as the fallback label when no real visitor name is known, with the short code
   kept as a small, deliberately faint trailing detail rather than dropped - the author's own reasoning
   for keeping it: collision probability is low with this pool, but not zero, and a faint tie-breaker
   costs nothing.
4. **Where the name comes from, decided over several turns**: not a CLDR library (bundle cost, and
   this pool is small and curated - the identical "hand-roll it, `ADR-0162`'s own precedent" reasoning
   `phoneFormat.ts` already gives for a different narrow, curated need). Not a bilingual table in
   `Ago.Chat.Domain` either - the author's own objection: Domain should not carry translated text,
   only stable facts. **Final shape: the emoji glyph itself is the i18n lookup key**, in each client's
   own existing string table (`ago-widget`'s `src/i18n/{ru,en}.ts}`-shaped mechanism, `ago-console`'s
   own i18n, and Android's `strings.xml`, `26-10`) - `{"🦉": "Сова"}` in the Russian table, `{"🦉":
   "Owl"}` in the English one. **`Ago.Chat.Domain` needs no new field of any kind for this** - the
   glyph already crosses the wire today, unchanged.
5. **The one real risk of keying by the glyph itself, named rather than left implicit**: emoji can
   carry an invisible Unicode variation selector (`U+FE0F`) that makes two visually identical glyphs
   byte-different. If `VisitorEmojiDictionary.cs`'s own literals and each client's own i18n table are
   typed independently, a mismatch silently drops a name with no error. **Mitigation, stated as an
   instruction, not left to chance**: every client's i18n table copies each glyph byte-for-byte from
   `VisitorEmojiDictionary.cs` - never retyped from an OS emoji picker or any other source.

## Scope

- **`ago-console`**: `visitorEmojiPrefix`/`visitorDisplayPrefix` (`workspace/visitorEmoji.ts`) render
  the badge composition wherever they build a visitor's avatar today
  (`ConversationList.tsx`'s two list variants, `ConversationPage.tsx`'s open-dialog header,
  `25-162`'s own `.ago-visitor-emoji` styling) - font-size +15% on the creature, badge food emoji with
  no background circle. When `visitorName` is absent, the fallback label becomes each emoji's own
  localized name (`Сова · Клубника`) rather than the bare glyphs, with the short code appended faint
  and small. When a real name is known, existing behavior is unchanged (the name already wins).
- **A new i18n table**, keyed by glyph, in whichever of `ago-console`'s existing i18n files fits its
  own convention - one English name and one Russian name per `Creatures`/`Foods` member (40 entries
  total against today's two twenty-member lists), copied byte-for-byte from
  `VisitorEmojiDictionary.cs`.
- **`ago-widget` is explicitly out of scope** - confirmed by reading `visitorEmoji.ts`'s own doc
  comment: the visitor's emoji-pair identity is an *operator-side* memory aid, rendered only in the
  console, never shown to the visitor themselves in the widget.
- **The Android mockup Artifact and `ago-android/docs/plan.md`** get the identical correction: every
  avatar becomes the badge composition (not the round-2 worker's side-by-side pair), and every
  placeholder visitor label becomes a localized name (`Сова · Клубника`, small faint id after it) -
  not the mockup's own invented `Гость <hex>` placeholder text, which does not match anything the real
  console actually renders (confirmed: no `"Гость"` string exists in `ago-console/src/i18n/*.ts`
  today).

## Out of scope

- Any change to `Ago.Chat.Domain`, the wire contract, or a migration - explicitly, after two earlier
  drafts of this item proposed exactly that and were both walked back.
- `ago-widget` - confirmed not applicable.
- Widening the emoji pool itself, or changing which two categories exist - explicitly declined; the
  original "near-duplicate animal faces" observation that opened this item is not being separately
  addressed here (a smaller, later item if it still matters once the badge composition itself is
  shipped and reviewed - the bigger, centered icon may already read distinctly enough that fixing the
  list's own content stops being necessary).

## Done when

- [ ] A visitor's avatar renders as the badge composition (centered creature emoji, `+15%`, foodless
      badge with no background circle) everywhere the console builds one today.
- [ ] A nameless visitor's label reads as `{Localized creature} · {Localized food}` followed by a
      small, faint short code - proven in both the Russian and English console locales.
- [ ] A named visitor's own behavior is provably unchanged.
- [ ] The new i18n table's every entry is confirmed to use the exact glyph literal from
      `VisitorEmojiDictionary.cs` (a test or a build-time check catching a mismatch is stronger than a
      one-time manual copy - name which was chosen and why).
- [ ] The Android mockup Artifact and `ago-android/docs/plan.md` both show the badge composition and
      localized names, replacing the round-2 pair-and-hex-code treatment.
- [ ] `ago-console` typecheck/lint/test all green; no `ago-chat`/`ago-widget` change of any kind.
