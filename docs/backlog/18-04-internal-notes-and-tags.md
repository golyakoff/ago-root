# Internal notes and tags on a conversation

- **Stage**: 18
- **Status**: done (2026-08-29, `ago-chat#121` + `ago-console#59`) — see Outcome below
- **Depends on**: nothing

## Goal

An operator can leave a note on a conversation that the visitor never sees, and label it so it can be
found and counted later.

## The one thing this item must not get wrong

**A note is invisible to the visitor, and the cost of being wrong is a person reading what was written
about them.** That makes it unlike every other message in the system, and it means the boundary cannot
rest on the console remembering to filter: the visitor-facing read path must be incapable of returning
one. `GetConversationHistoryHandler`'s visitor entry point is where that is enforced, and a test that
proves a note never appears in a visitor's history is the item's most important line.

Whether a note is a `messages` row with a kind, or its own table, follows from that: a separate table
cannot leak through a query that forgets a predicate, because there is no predicate to forget.

## Context to read first

`ago-chat/src/Ago.Chat.Application/UseCases/GetConversationHistory/` — the two entry points, visitor
and operator, and why they are separate (`1-02`). `docs/architecture/data-model.md` — where a new table
goes and what its indexes cost. `docs/architecture/personal-data.md` — a note is personal data about a
visitor written by someone else, so it is in scope for erasure (`16-02`) and export (`16-03`), and both
items need telling. `docs/backlog/18-01-conversation-search.md` — tags are the cheap half of finding
things, and the two want to agree on what a filter is.

## Scope

- Notes on a conversation, author and timestamp recorded, never reachable from any visitor-facing path.
- Tags on a conversation, per site, with a small management surface.
- Filtering the queue and the admin list by tag.
- A test proving a note cannot appear in a visitor's history, written before the feature.
- `16-02` and `16-03` updated: notes and tags are tenant data that erasure removes and export includes.

## Out of scope

- Mentioning another operator in a note, and any notification from it — that is `18-05`'s territory
  plus a notion of addressing that does not exist.
- Tags with meaning to automation (routing, SLAs). Labels first.

## Done when

- [x] A note is visible to operators and provably unreachable by a visitor.
- [x] Conversations can be tagged and filtered by tag.
- [x] `16-02` and `16-03` name notes and tags among what they cover.

## Open questions

None. Where a note is stored is this item's decision, argued from the leak-proofing above.

## Outcome

Shipped as nine new handlers across `ago-chat#121` (notes: `AddConversationNoteHandler`/
`GetConversationNotesHandler`, `conversation_notes` its own table; tags: `CreateTag`/`RenameTag`/
`DeleteTag`/`ListTags`/`GetConversationTags`/`TagConversation`/`UntagConversation`, `tags` +
`conversation_tags`) plus `ago-console#59` (Notes/Tags panels, a `/settings/tags` management screen,
a tag filter on the queue and the admin list). `docs/architecture/tenant-isolation.md`,
`data-model.md` and `personal-data.md` all updated in the same change as this Outcome.

**The leak-proof test, run before the code that would make it pass, as the item's own Scope
required**: `NoteLeakProofTests` proved against a real Postgres — fails-before confirmed by
temporarily `UNION`-ing a note into `ConversationReadStore.GetHistoryAsync`'s SQL (simulating the
rejected "note as a `messages` row" design) and watching the note's own body appear in what the
handler was about to hand the visitor.

**A real gap found and fixed while landing, beyond this item's own diff**: `conversation:note_write`/
`conversation:tag` were defined and both new handlers checked them, but neither `RegisterSiteHandler`'s
nor `MintDemoTenantHandler`'s Operator role seed ever granted either — every real operator on every
real site would have been permanently `Forbidden` from the entire feature, despite every unit and
integration test passing (none of them exercise real role seeding). Fixed in both handlers and in the
`ago-deploy` demo-tenant seed script (`ago-deploy#89`), plus the two exact-match seeding tests that
should have caught it.
