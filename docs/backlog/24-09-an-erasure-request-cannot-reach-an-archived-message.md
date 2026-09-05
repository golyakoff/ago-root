# erasing a conversation erases its archived copy too

- **Stage**: 24
- **Status**: ready
- **Depends on**: `13-06` (shipped — the archive this must reach), `16-02` (shipped — the erasure job)
- **Decision**: `docs/adr/0031-*` — "archiving moves the liability, it does not end it"

## Goal

A conversation erased on request leaves no copy of its messages standing in the retention archive.

## What is actually true today, verified 2026-09-05 (`24-06`)

`ConversationErasureJob`'s own remarks say, in the code, today:

> Nothing archives today - `13-06`, the real archive writer, is not built […] This job does not reach
> an archive because there is nothing to reach.

That was accurate when `16-02` was written and stopped being accurate when `13-06` shipped
`MessageArchiveJob`, `MessageArchiveWriter` and the `message_archives` manifest. `personal-data.md`'s
`message_archives` row already names the consequence — "`16-02`'s own erasure must be extended to reach
it, per `adr/0031`'s own Consequences" — and nothing has.

So today: erasing a conversation removes its MinIO objects, its messages, its notes, its tags, its
visitor's contact details and its row. Any month of that conversation's history already archived
survives, inside a per-site, per-class `.zip` in object storage that nothing deletes on any timeline.

The erasure job even names the fix location: "the obvious single place to add 'and delete the archived
copy too' is `EraseConversationAsync`, as a clearly-commented step".

## Why this is a gap rather than an oversight

Two items shipped in the order that made sense for the product and the wrong order for this seam.
`16-02` correctly refused to build a fake archive-erasure port against an archive that did not exist —
that would have been exactly the premature generalisation `CLAUDE.md` warns against. `13-06` then built
the archive and, reasonably, did not go looking for a job in a different item that had already declared
itself finished. The stale comment in the erasure job is the visible edge of it.

## Scope

- `ConversationErasureJob` reaches the archive: identify the archived objects covering the erased
  conversation's messages and remove that conversation's content from them, or record why a whole-object
  rewrite is the only available shape and what that costs.
- The same question for `SiteErasureJob` — a `message_archives` row cascades with the site, and
  `personal-data.md` records that the `.zip` is then orphaned in storage.
- Update `ConversationErasureJob`'s own remarks, which currently state something false.
- `personal-data.md`'s `message_archives` row updated to say what now removes it.

## Out of scope

- The tenant **export** archive (`16-03`'s `exports/site/...zip`), which erasure also does not reach.
  Different artifact, different purpose, different lifetime — and pruning it is a retention decision
  rather than an erasure one. Named here so it is not assumed covered.
- Backups. `adr/0050`'s 30-day window is the deliberate answer and is not reopened here.

## Done when

- [ ] An erasure that runs after a conversation's messages were archived leaves no copy of them in the
      archive — asserted by an integration test that archives first and erases second.
- [ ] `ConversationErasureJob`'s remarks describe the system that exists.
- [ ] `personal-data.md`'s `message_archives` row names the removal path.

## Open questions

- **Rewrite the object, or delete it whole?** An archive object covers one site, one retention class,
  one month — many conversations. Deleting it to erase one conversation destroys other people's
  transcripts; rewriting it is a read-modify-write on an object the prune job's gate depends on. This
  is the real design question and it should be decided before implementation, possibly as an ADR.
