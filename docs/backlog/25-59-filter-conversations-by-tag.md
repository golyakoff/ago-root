# 25-59 · Filter conversations by tag

- **Stage**: 25
- **Status**: ready
- **Verified**: 2026-09-12 — `ConversationTagsPanel.tsx` confirmed as the real vocabulary source
  (`siteTags`, fetched via `tagsApi.ts`, `18-04`). No existing multi-select filter (checkbox-style,
  AND/OR) exists anywhere else in the console to match — searched for one, found none — so this
  item's own AND-by-default fallback applies as written, not a convention borrowed from elsewhere.
- **Depends on**: nothing — `18-04`/`19-02` already built the tag dictionary and per-conversation
  tagging this item filters by; confirmed shipped, not built here
- **Found**: 2026-09-12, `feedback.md`, narrowed by investigation — the tag mechanism itself (a real
  per-tenant dictionary, autocomplete, `Operator`/`Ai` source, vocabulary and breakdown-report pages)
  already exists and works exactly as the author guessed it should. **The one real, confirmed gap**:
  nothing filters or searches conversations by tag anywhere in the console today.

## Scope

- Add a tag filter to the Диалоги panel (the conversation list) — an operator can narrow the visible
  list to conversations carrying one or more selected tags, drawn from the tenant's own tag
  dictionary (`ConversationTagsPanel.tsx`'s own vocabulary source), the same autocomplete-from-
  dictionary interaction the existing per-conversation tag-apply control already uses.
- Multiple tags selected filter as AND (a conversation must carry all selected tags) unless a
  narrower reading is found to already exist elsewhere in this console's own filter conventions — if
  another list screen already establishes an OR-by-default convention for multi-select filters, match
  it instead of inventing a new rule.

## Where this is likely to go wrong

- **This item does not touch the tag dictionary, tag application, or the breakdown report** — those
  are shipped and correct (`18-04`/`19-02`). Scope is the filter control and the query it drives,
  nothing about how tags are created or applied.

## Done when

- [ ] The Диалоги panel offers a tag filter sourced from the tenant's own real tag dictionary.
- [ ] Selecting one or more tags narrows the visible conversation list to matching ones.
- [ ] Clearing the filter returns to the unfiltered list.
