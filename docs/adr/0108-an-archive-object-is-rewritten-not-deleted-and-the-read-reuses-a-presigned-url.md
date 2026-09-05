# ADR-0108: An erased conversation's archive lines are rewritten, not deleted whole - and the read reuses a presigned URL, not a widened port

- **Status**: Accepted
- **Date**: 2026-09-05
- **Stage**: 24

## Context

`13-06` shipped `MessageArchiveJob`: once a site's messages for one retention class and one calendar
month age past their live window, they are written to a single object in object storage
(`archive/messages/{siteId}/{class}/{period}.zip`, `MessageArchiveWriter`) and only then dropped from
`messages`. `16-02` shipped conversation and site erasure before that archive existed, and its own
remarks said so plainly: "nothing archives today... this job does not reach an archive because there
is nothing to reach." `13-06` landed afterwards and nobody went back - `personal-data.md`'s
`message_archives` row has named the gap since, and `backlog/24-09` is the item that closes it.

Two things make this harder than "call `IFileStorage.DeleteAsync`", which is how every other
erasure step in this codebase removes an object:

**One archive object is not one conversation's data.** `adr/0031`'s Decision 3 is "one object per site
per period" - a whole retention class's whole calendar month, for every conversation that site had
during it. `MessageArchiveWriter.WriteMessagesAsync`'s own query is `where site_id = @siteId and
retention_class = @retentionClass and created_at >= @periodStart and created_at < @periodEnd`, with no
`conversation_id` predicate at all. Deleting the object to satisfy one conversation's erasure request
would destroy every other visitor's transcript archived alongside it in the same period - the exact
mistake `backlog/24-09`'s own Scope warns against ("deleting the whole object to erase one conversation
would destroy other people's transcripts").

**`IFileStorage`'s own contract is presign-only.** Its doc comment states the design directly: "every
method here either issues a short-lived presigned URL a client uses directly against storage, or
answers a metadata question, never streams a byte itself." That was written for the attachment path -
end-user uploads and downloads that must never route through the API host's own bandwidth
(`CLAUDE.md`: "attachments — bytes never pass through the API"). A rewrite needs to *read* an existing
object's bytes as well as write new ones, which is not one of that port's four methods.

## Decision

**Rewrite the object, in place, at the same key - never delete it whole for a per-conversation
erasure.** `ConversationArchiveEraser` (`Ago.Chat.Worker`) downloads each of a site's archive objects
(`IMessageArchiveRepository.ListForSiteAsync`), drops the `messages.jsonl`/`attachments.jsonl` lines
whose `conversationId` matches the one being erased, and re-uploads the result to the identical object
key. A period that does not mention the conversation at all is left untouched - no download becomes a
re-upload for the common case. The manifest (`manifest.json`) is carried through unchanged; only the
two per-row files are filtered.

**No change to `IFileStorage`.** The read and write both go through the same presigned-URL shape
`MessageArchiveJob.ArchiveOneAsync` already established for the write half: `CreateDownloadUrlAsync`/
`CreateUploadAsync` presign a GET/PUT, and `Ago.Chat.Worker`'s own `HttpClient` — never the API host's
— does the actual byte transfer directly against object storage. `ConversationArchiveEraser` adds
nothing to the port; it is the first caller in this codebase to use `CreateDownloadUrlAsync` for a
*read* of an object's own content rather than only handing the URL to an end user, but the port already
had the method.

**A whole-site erasure deletes the object outright, once every conversation has already emptied it.**
`SiteErasureJob.ProcessSiteAsync` gates on every one of the site's conversations being drained first
(`HasAnyConversationAsync`) - which, since this decision, means every one of them has already been
through `ConversationArchiveEraser`. By the time `SiteErasureJob` reaches its own archive step, each
object the site has is already an empty shell (a manifest plus two empty `.jsonl` files), so deleting it
outright removes no other tenant's data and no in-flight rewrite. `message_archives`'s own row still
cascades with the site as before; the object it names no longer survives that cascade as an orphan.

**Every archived period is checked for a conversation-erasure request, not only ones its still-live
messages point at.** A conversation whose oldest messages already aged past their window has nothing
left in `messages` to say which periods to look at - the partition that held them was already dropped,
per `adr/0031`'s own archive-then-drop ordering. `message_archives` is the only remaining source of
"which periods this site has ever had archived," so every row it lists is opened.

**A failure here is allowed to fail the conversation's erasure for this cycle, not be tolerated.**
Every other object-storage failure in `ConversationErasureJob` (deleting an attachment's own object) is
caught, logged and left as an orphan, because the row that mattered is already going regardless. Here
it is the opposite: silently finishing a conversation's erasure while its archived copy still stood
would be precisely the defect this ADR exists to close, so a download or upload failure propagates,
leaving the conversation flagged (`erasure_requested_at` untouched) for the next cycle to retry - the
same idempotent-retry shape every other step in this job already relies on. The one tolerated case is a
`404` on the read: an archive row whose object is already gone is "nothing left to remove," the same
already-gone-counts-as-done idempotency `DeleteAsync`'s own S3 semantics give every other delete in this
codebase.

## Consequences

- **Conversation erasure's reliability profile changes.** It now depends on object storage being
  reachable for a *read* as well as a write, where before this it only ever wrote (attachment deletes)
  or read metadata. A storage outage can now leave a conversation's erasure incomplete (retried next
  cycle) in a way it could not before.
- **Conversation erasure's cost changes.** One conversation's erasure now costs up to one HTTP round
  trip per archived period the site has ever had - bounded by the site's own age and archive cadence
  (monthly, per class), not by the conversation's own size. A site with years of history across three
  retention classes pays tens of round trips per conversation erased, not one.
- **A rewritten object is smaller, byte-for-byte different, and re-uploaded under the same key and
  content type.** Nothing downstream keys off the object's ETag or byte-for-byte identity today
  (`GetMessageArchiveDownloadUrlHandler` only ever hands out a fresh presigned URL), so this is safe;
  a future feature that fingerprinted an archive object by hash would need to know this ADR exists.
- **`ConversationArchiveEraser` is a new caller of `CreateDownloadUrlAsync` for a read of an object's
  own bytes, not only a handoff to an end user.** Worth naming because it is a widening of *use*, not
  of the port's own contract - `IFileStorage`'s four methods are unchanged, and every other caller's
  behaviour is unaffected.
- **`SiteErasureJob` gains two new constructor dependencies** (`IFileStorage`, `IMessageArchiveRepository`),
  both already registered in the DI container for other reasons, so no new registration was needed for
  it specifically.
- **No EF migration.** Nothing about the schema changes - `message_archives`' existing columns and
  cascade are unchanged; this ADR is entirely a behavioural change to two Worker jobs and one new class.

## Alternatives considered

- **Delete the whole archive object once one conversation inside it is erased.** Rejected outright -
  `adr/0031`'s "one object per site per period" means this would destroy every other visitor's
  transcript archived in the same period, which is a worse outcome than the gap this ADR closes.
- **Widen `IFileStorage` with byte-level `Get`/`Put` methods.** Would have made the read/write
  mechanics slightly shorter in `ConversationArchiveEraser`, at the cost of reopening a port whose own
  doc comment states its "never streams a byte" contract as a deliberate property other callers may
  rely on reasoning about. Rejected because the existing presign-then-`HttpClient` shape
  `MessageArchiveJob` already established for the write half covers the read half with no port change
  at all - reusing an existing, working pattern beats widening a shared abstraction for one caller.
- **A per-conversation index into archives**, recording which periods mention which conversation, to
  avoid scanning every archived period on every erasure. Would reduce the round-trip cost named in
  Consequences, at the cost of a new table this item's own scope forbids adding (an EF migration is
  explicitly out of scope for `24-09`, and another in-flight item already holds the migration slot).
  Left as a future optimisation if the round-trip cost is ever measured and found to matter - `CLAUDE.md`
  rule 7 is the reason it is not built speculatively now.
- **Tolerate an object-storage failure during archive rewrite, the same way an attachment-object delete
  is tolerated.** Rejected: an attachment-object delete's failure leaves an orphan nobody's erasure
  claim depends on; an archive-rewrite failure that was silently tolerated would let a conversation's
  erasure report complete while its archived copy still stood - the exact defect this ADR exists to
  close, reintroduced by the wrong error-handling choice.
