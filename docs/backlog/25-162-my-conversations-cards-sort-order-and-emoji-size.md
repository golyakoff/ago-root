# 25-162 · "Мои" conversation cards: sort order and emoji size

- **Stage**: 25
- **Status**: ready — reported live 2026-09-19, queued behind `25-161`
- **Found**: 2026-09-19, live-testing the console's "Диалоги > Мои" ("Assigned to me") panel. Two
  small, related legibility issues on the same card list, bundled the way `25-154` already bundles
  several small live-found rendering issues under one item, since neither is worth its own number on
  its own:
  1. Cards are not sorted by recent activity - the author expects most-recently-active conversations at
     the top, oldest at the bottom, and today's order does not do that.
  2. The visitor emoji-pair icon on each card is too small to read at a glance ("почти не видно вообще"
     - practically invisible). Card layout as observed:
     ```
     [ big emoji ] Name, dialog number
                    Открыт XX, активен YY
     ```
     The same undersized emoji appears on the individual conversation page's own header too (e.g.
     "Диалог с 🦉🍌 `01a0b620`") - the fix should cover both places this icon renders, not just the
     list.

## Scope

- `ConversationList.tsx` (or wherever "Мои" sorts its own card list, `workspace/` per the panel's own
  code area): sort by most-recent-activity descending - confirm what "activity" already means
  elsewhere in this codebase (e.g. `ConversationsAttentionProvider.tsx`/`attention.ts` likely already
  carry a notion of "last activity" or "last message at" this can reuse rather than invent a second
  one) before adding a new field.
- The visitor emoji-pair rendering (wherever the "🦉🍌"-style pair is drawn - the card list and the
  conversation page header both) gets a real, deliberately larger size - a CSS/typography fix, checked
  against both places it renders so the two do not drift.

## Out of scope

- Any other card content or layout change beyond sort order and emoji size.
- "Все диалоги"/"Поиск" panels - this item is about "Мои" and the conversation page header
  specifically, where the report was made; if the same issue is confirmed elsewhere, that is a
  separate finding, not silently rolled in here.

## Done when

- [ ] "Мои" cards render most-recently-active conversation first, oldest last - proven by a test with
      cards seeded out of order
- [ ] The visitor emoji-pair icon is visibly larger on both the card list and the individual
      conversation page header, confirmed live, not only by a snapshot
