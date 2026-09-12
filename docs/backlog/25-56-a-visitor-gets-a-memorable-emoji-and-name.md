# 25-56 · A visitor gets a memorable emoji pair and their own name, everywhere the short code appears

- **Stage**: 25
- **Status**: done — `ago-chat#262`, `ago-chat#264`, `ago-console#202`, `ago-console#208`
- **Verified**: 2026-09-12 — the 8-character code is confirmed real: `visitorId.slice(0, 8)`, rendered
  at `ago-console/src/workspace/ConversationList.tsx:102,167` (the conversation-switching panel, both
  its list variants) and `ago-console/src/pages/ConversationPage.tsx:705` (the open-dialog header) —
  exactly the two locations this item names and no others. `Ago.Chat.Domain/Visitor.cs` exists as the
  natural home for a new per-visitor emoji-pair field.
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md` — the author's own idea, sharpened into concrete requirements
  through direct questions (recorded below) rather than left to guesswork

## What is actually true

A conversation is identified in the operator console by an 8-character short code (e.g.
`01a08fcd`) alone. Two such codes look identical at a glance, which the author named as a real
cognitive-load problem — nothing helps an operator recognize "this is the same visitor as before" or
even "this is a different conversation from that one" without reading the full code carefully.

## The decisions, all the author's own, 2026-09-12

1. **Whose identity it is: the visitor's, not a per-operator assignment.** One emoji pair per
   visitor, the same pair shown to every operator who sees that visitor's conversation — not a
   private mnemonic each operator maintains separately.
2. **Two emoji, from two different groups** — one from an animal/bird/creature group, one from a food
   group (the author's own examples: 🐔🍊, 🐠🥝, 🐳🌭). Two, not one, despite the extra cognitive load
   the author themself named, because it meaningfully increases the number of distinct combinations.
3. **Assignment is a fixed, shipped dictionary** — pick two lists (creatures, food), each with enough
   neutral, visually-distinct members that combinations don't repeat constantly for a small tenant.
   Not a per-tenant configurable list; this is a memory aid, not a branding surface.
4. **Repeats are acceptable.** A new visitor may be assigned a combination another visitor already
   has — this is not a uniqueness guarantee, it is a mnemonic; the visitor's own name (when known)
   provides the actual disambiguation repeats might need.
5. **Assigned once, permanent for that visitor** (not re-rolled per conversation) — this follows
   directly from decision 1 (a visitor-level identity, not a conversation-level one).
6. **Where it appears — confirmed explicitly, this exact list and no more:**
   - The conversation-switching panel (the list that today shows only the 8-character code) — the
     emoji pair (and the visitor's own name, if known) render beside the short code, not replacing it.
   - The header of the currently-open dialog.
   - **Explicitly not**: inside the dialog transcript next to per-message "who wrote this" labels, and
     explicitly not anywhere in the widget (visitor-facing side). This is an operator-side memory aid
     only.

## Scope

- A new per-visitor field: an emoji pair, assigned once at first contact (or first time this item's
  own migration/backfill runs for an existing visitor), drawn from the two fixed dictionaries above,
  never reassigned afterward.
- Render `{emoji}{emoji} {name-if-known} {short-code}` in the conversation-switching panel and the
  open-dialog header, exactly matching the shape:
  - `🐔🍊 Иван Иванов 01a08fcd | Открыт 1h 1m` (name known)
  - `🐔🍊 01a08fcd | Открыт 1h 1m` (name not yet given)
- If the visitor later provides a name mid-conversation, the display updates to include it without
  requiring a reload.

## Where this is likely to go wrong

- **Do not key the emoji assignment by conversation.** The whole point (decision 1) is that the same
  visitor gets the same pair across every conversation they ever have with this tenant — key it to
  the visitor's own identity, not the conversation's.
- **Do not build per-tenant dictionary configuration** — decision 3 is explicit that this is a fixed,
  shipped list, not a settings screen.
- **Existing visitors need the field backfilled**, not left null forever — decide and state how (a
  migration assigning pairs to all existing visitor rows, or lazy assignment on first render — either
  is fine, state which).

## Outcome

Landed in two waves. **Emoji pair** (`ago-chat#262`, `ago-console#202`): `Visitor.EmojiCreature`/
`EmojiFood`, two emoji drawn once from `VisitorEmojiDictionary`'s fixed 20+20 lists via
`IVisitorEmojiPairGenerator`, assigned at first contact and never reassigned. Existing visitors
backfilled by a real EF migration (`Stage25AddVisitorEmojiPair`), not left null — the column stays
nullable at the DB level regardless, since the actual guarantee is enforced by the two creation call
sites, not a schema constraint (~90 test fixtures construct a bare `Visitor`).

**Visitor's own name** (`ago-chat#264`, `ago-console#208`) — the piece that had to wait on `25-62`
(the `Other`→`Name` rename): sourced from a `VisitorContactDetailKind.Name` row, batch-loaded
alongside the emoji pair (`GetOperatorQueueHandler`'s own `IVisitorContactDetailRepository.GetNamesForVisitorsAsync`,
a `left join lateral` in `ConversationReadStore`'s hand-written queries). No unique index exists on
`(visitor, kind)`, so a repeat submission resolves to the most recent by `RecordedAt`.

Both render in exactly the two named places (`ConversationList.tsx`'s two rows, `ConversationPage.tsx`'s
open-dialog header) via `visitorEmoji.ts`'s `visitorDisplayPrefix`, in the exact
`{emoji}{emoji} {name} {shortCode}` format, falling back byte-identically to emoji-only when no name
exists. Both update live with no new plumbing — the same `ConversationSummaryDto` the workspace
already refreshes on its 15s poll and on assignment/send events.

## Done when

- [x] Every visitor has a stable emoji pair, assigned once, drawn from the two fixed dictionaries,
      never reassigned.
- [x] The pair (and name, if known) renders in the conversation-switching panel and the open-dialog
      header, in the exact format shown above — and nowhere else (not in-transcript, not in the
      widget).
- [x] A visitor's name appearing mid-conversation updates the display live.
- [x] Existing visitors (pre-dating this item) get a real, stated backfill strategy, not a permanently
      empty pair.
