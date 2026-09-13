# 25-78 · Erasure does not yet drain a visitor's own restriction history

- **Stage**: 25
- **Status**: ready
- **Depends on**: `23-69`/`23-77` (done, `ago-chat#282`/`ago-console#221`) — built `visitor_restrictions`.
  `16-02` — the erasure cascade this item's own gap sits next to.
- **Found**: 2026-09-13, landing `23-69`/`23-77`. Named plainly in `docs/architecture/personal-data.md`'s
  own new `visitor_restrictions` row rather than silently assumed covered: `16-02`'s conversation/visitor
  erasure reaches `conversation_notes`/`visitor_contact_details` explicitly, the same way it should reach
  this new table, and does not yet.

## What is actually true today

`visitor_restrictions` cascades from `sites` and from `visitors` at the database level (`ON DELETE
CASCADE`), so a hard-deleted `visitors` row takes its restrictions with it automatically. `16-02`'s own
erasure path does not hard-delete a `visitors` row, though — it drains specific tables explicitly
(`ConversationErasureQuery.DeleteNotesForConversationAsync`/`DeleteContactDetailsForVisitorAsync` and
their siblings), the same "primary mechanism is explicit, cascade is defence in depth" shape
`personal-data.md` already documents for every other visitor-scoped table. `visitor_restrictions` was
not added to that explicit drain when it was built — an erased visitor's own restriction history
(*was this person muted for spam, or blocked*) currently survives an erasure request that is supposed
to take everything about them.

## Why this is worth its own number rather than folded back into `23-69`/`23-77`

Both of those items are done, merged and independently verified — this is a real, separate gap their
own build found and named, not a remainder they left unfinished by omission. CLAUDE.md rule 14: a
found defect gets a number of its own.

## Scope

- `16-02`'s erasure path drains `visitor_restrictions` for the visitor being erased, the same explicit
  way it already drains `conversation_notes`/`visitor_contact_details` — not left to the `ON DELETE
  CASCADE` backstop alone, matching this codebase's own stated preference for an observable, counted
  drain over a silent cascade.
- Decide, and state, whether a restriction whose `source_conversation_id` names a *different*,
  not-yet-erased conversation should be drained too, or only ones tied to the conversation actually
  being erased — `visitor_restrictions` is scoped to the visitor, not to one conversation, so "erase
  this conversation" and "erase this visitor" may need different answers here.

## Out of scope

- Anything about `23-69`/`23-77`'s own already-shipped mechanism beyond this one gap.

## Done when

- [ ] `16-02`'s erasure explicitly drains a visitor's `visitor_restrictions` rows, observable in the
      erasure job's own count, the same way its existing drains already are.
- [ ] The conversation-scoped-vs-visitor-scoped erasure question above is answered and the answer is
      stated in `personal-data.md`'s own `visitor_restrictions` row, not left as an open flag.
