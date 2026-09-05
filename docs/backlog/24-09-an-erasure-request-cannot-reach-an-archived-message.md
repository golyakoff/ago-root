# erasing a conversation erases its archived copy too

- **Stage**: 24
- **Status**: done (2026-09-05) — see Outcome below
- **Depends on**: `13-06` (shipped — the archive this must reach), `16-02` (shipped — the erasure job)
- **Decision**: `docs/adr/0031-*` — "archiving moves the liability, it does not end it"; `docs/adr/0108-*`
  — the rewrite-vs-delete-whole decision this item's own Open questions asked for

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

- [x] An erasure that runs after a conversation's messages were archived leaves no copy of them in the
      archive — asserted by an integration test that archives first and erases second
      (`ConversationErasureIntegrationTests.ErasingOneConversation_RemovesItsOwnLinesFromAnArchiveItSharesWithAnotherConversation`,
      real Postgres and real MinIO; fails-before independently confirmed by disabling the new archive
      step and observing the exact assertion fail).
- [x] `ConversationErasureJob`'s remarks describe the system that exists.
- [x] `personal-data.md`'s `message_archives` row names the removal path.

## Open questions

None — resolved by `docs/adr/0108-*` below.

- ~~**Rewrite the object, or delete it whole?**~~ **Decided: rewrite, for a per-conversation erasure;
  delete whole, for a whole-site erasure only once every conversation has already emptied it via the
  rewrite path.** An archive object covers one site, one retention class, one month — many
  conversations — so deleting it whole to satisfy one conversation's erasure would destroy other
  people's transcripts; rewriting it is a read-modify-write, done through the same presigned-URL shape
  `MessageArchiveJob` already uses for its own upload, with no change to `IFileStorage`'s own contract.
  Full reasoning, alternatives and consequences in `docs/adr/0108-*`.

## Outcome

Shipped 2026-09-05. `ConversationArchiveEraser` (`Ago.Chat.Worker`) is the new piece: given a site and a
conversation id, it lists every archive object the site has (`IMessageArchiveRepository.ListForSiteAsync`),
downloads each one via the existing presigned-GET shape, drops the `messages.jsonl`/`attachments.jsonl`
lines naming that conversation, and re-uploads the result to the same key — skipping the upload entirely
for a period the conversation never touched. `ConversationErasureJob.EraseConversationAsync` calls it
once per conversation, immediately before the conversation row itself is deleted (not before — see that
method's own remarks on why the ordering is load-bearing, not cosmetic: the row is what
`erasure_requested_at` lives on, and the retry loop depends on it still existing if this step fails).
`SiteErasureJob.ProcessSiteAsync` deletes each of the site's own archive objects outright, once its own
gate confirms every conversation has already been drained through the rewrite path — closing the
"`message_archives` cascades with the site, and the `.zip` is orphaned in storage" half of this item's
own Scope.

**This does change conversation erasure's reliability and cost profile, and the report says so
plainly**: it now depends on object storage being reachable for a read as well as a write (a failure
here is allowed to leave the conversation flagged for retry, not tolerated the way an attachment-object
delete failure is — silently completing while an archived copy stood would be the exact defect this item
closes), and it can cost one HTTP round trip per archived period the site has, not only per attachment.

No EF migration — `23-06`'s held the slot, per this item's own standing instruction, and nothing about
the schema needed to change; `message_archives`' existing columns and cascade are untouched.
