# ADR-0072: Tenant export format, versioning, and why attachment bytes are referenced, not embedded

- **Status**: Accepted
- **Date**: 2026-08-28
- **Stage**: 16

## Context

`16-03` builds the first path by which a tenant can take their own data out of AGO Chat: an operator
triggers an export from the console, `Ago.Chat.Worker` assembles an archive asynchronously (the same
job shape `16-02`'s `SiteErasureJob` established), and the console polls until it can hand the
operator a download link. Its own backlog item names two decisions explicitly as the item's main
design questions and asks that both be written down with their reasoning, not defaulted past: whether
the archive embeds attachment bytes or references them, and whether the format is versioned. A third
fact falls out of `adr/0031` (2026-08-25), decided after `16-03` was scoped but before it was built:
this same format becomes the retention archive's own on-disk shape once `13-06` ships, so a decision
made here is binding on files that will exist independently of any tenant ever asking for an export.

## Decision

### Attachment bytes: referenced by presigned URL, not embedded

`IFileStorage` (`Ago.Platform.Abstractions`, `adr/0004`'s port-per-external-resource rule) has exactly
four methods, and none of them returns bytes - only `CreateDownloadUrlAsync`, which returns a `Uri`.
Embedding attachment bytes in the archive would require adding a byte-returning method to that port,
which is an `ago-platform` change and out of this single-repository item's scope (`repositories.md`).
Referencing needs nothing new: `SiteExportArchiveWriter` writes `attachments.jsonl` with each row's
metadata plus a presigned download URL, minted the same way `GetAttachmentDownloadUrlHandler` already
mints one for the console's own attachment previews.

This also keeps `file-storage.md`'s own rule in spirit - "file bytes never pass through the API
process" - one step further than its letter requires: the export job runs in `Ago.Chat.Worker`, not
`Ago.Chat.Api`, so the rule's literal scope does not even reach it, but the same reasoning (a process
holding tens of thousands of connections should not also hold multi-megabyte buffers on user-driven
demand) applies just as well to a background job whose trigger is still, ultimately, an operator
clicking a button.

**Named cost, not a silently accepted one**: the export decays. `SiteExportJobOptions.
AttachmentUrlLifetime` is **7 days** - not a guess, but the actual ceiling AWS SigV4 (and MinIO's
compatible implementation) places on `X-Amz-Expires` for a presigned URL. A tenant who downloads the
manifest and its JSONL rows but waits past that window has attachment *metadata* with links that no
longer resolve, not the bytes. The remedy is triggering a fresh export - consistent with `16-03`'s
own Out-of-scope line ruling out continuous or scheduled export, so "the export is a point-in-time
snapshot that ages" is already the product's stated shape, not a gap this decision introduces.

### Format: JSON Lines per store, inside a single zip, with an explicit `formatVersion`

One `.zip` per export (`exports/site/{siteId}/{exportId}.zip`), containing a `manifest.json`
(`{formatVersion, siteId, exportedAt, attachmentBytes, stores: [...]}`) plus one JSON Lines file per
store - `site.json` is the one exception, a single object rather than a line-per-row file, since a
site is exactly one row. JSON Lines over a single large JSON array for the same reason `4-05`'s
`MessageBatchWriter` and every Dapper read store in this codebase favour a forward-only reader over
materializing a collection: `SiteExportArchiveWriter` reads each store through an `NpgsqlDataReader`
and writes one line per row directly into the corresponding zip entry, so no `List<T>` ever holds a
tenant's full history, matching the "streamed, not buffered" requirement the backlog item states as a
hard constraint (`nfr.md`'s targets are not suspended because an export is running).

**`formatVersion: 1`, decided rather than deferred.** `adr/0031` makes this exact format the retention
archive's own on-disk shape too (`13-06`, not yet built) - a change to any row's shape after that item
ships is a change to files that already exist and cannot be rewritten in place. A version field is
what lets a future reader (a restore tool, a support script, a human) tell which shape a given archive
was written in, at the cost of one integer field now. Deferring the version to "add it when a second
shape exists" would mean every archive written before that point has no marker to distinguish it from
whatever comes after - exactly the situation a version field exists to prevent, and the reason this
item pays the one-field cost immediately rather than waiting for evidence it is needed.

### Cross-tenant isolation: enforced in the query itself, not only in the handler

`GetSiteExportStatusHandler` checks `Permission.SiteExport` before doing anything else, but the
second half of the guarantee - that an operator holding `SiteExport` on *their own* site cannot pull
a different tenant's export by guessing or intercepting its id - is enforced in
`ExportRequestRepository.GetAsync`'s own SQL: `WHERE id = @id AND site_id = @siteId`, not a
post-fetch comparison in application code. A nonexistent id and an id belonging to a different site
are deliberately indistinguishable (both `404 Export.NotFound`), matching `16-02`'s own
`RequestConversationErasureHandler` precedent for the identical "never confirm existence across a
tenant boundary" reasoning. Proven with `SiteExportIntegrationTests` against a real Postgres, not
asserted from the query text.

## Consequences

- `docs/architecture/file-storage.md` gains a section recording the attachment-reference decision and
  its 7-day-decay cost, alongside the upload/download flow it now sits next to.
- `docs/architecture/personal-data.md` gains rows for `export_requests` (metadata only - no personal
  content) and the export archive itself, the second one filling in the row `adr/0031`'s own "Retention
  archive" entry already anticipated by name ("in `16-03`'s tenant-export format") before this item
  existed to make that format real.
- **`13-06`'s retention archive inherits this format and this version number as its starting point.**
  Any future change to a row's shape is a `formatVersion` bump, not a silent rewrite - stated here so
  `13-06`'s own author does not have to rediscover the load-bearing fact from scratch.
- `docs/architecture/authorization.md`'s existing per-conversation/per-site ownership-comparison
  discipline gains a second concrete instance (`GetVisitorHistoryHandler`'s `18-07` entry is the
  first): a guard enforced in the query, not only in the handler that calls it.
- A known, separate gap this item does not fix: `ago-deploy/seed/create-demo-tenant.sh`'s Admin
  permission array does not grant `site:export` (or, from before this item, `site:erase`/
  `conversation:erase`) - a demo tenant seeded by that script cannot exercise this feature end to end
  until the script's own permission list is brought current. Tracked separately, not blocking this
  change.

## Alternatives considered

- **Embedding attachment bytes in the archive.** Rejected: no port method returns bytes today, and
  adding one is an `ago-platform` change this single-repository item cannot make. Would also produce
  archives whose size is unbounded by anything this item controls, for a tenant with many large
  attachments - directly in tension with "streamed, not buffered."
- **A single large JSON array per store, or one JSON document for the whole export.** Rejected: either
  shape requires materializing the full collection in memory before it can be serialized, which is
  exactly what "streamed, not buffered" rules out for a tenant with a year of conversation history.
- **No format version, added only once a second shape exists.** Rejected: `adr/0031` already commits
  a second consumer (the retention archive) to this exact format before that consumer is built, so
  "wait for evidence" is not available here the way it would be for an isolated, single-purpose
  format - the second consumer is already decided, only not yet implemented.
- **A shorter or longer attachment-URL lifetime than 7 days.** Rejected as arbitrary: SigV4's own
  protocol ceiling is a real constraint, not a choice, so using anything less would trade away
  usefulness for no protocol reason, and nothing longer is possible to request in the first place.
