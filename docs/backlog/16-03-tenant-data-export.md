# Export: a tenant can take their data out

- **Stage**: 16
- **Status**: done (2026-08-28, `ago-chat#113`) — see Outcome below
- **Depends on**: `16-01-personal-data-map-and-residency-constraint.md` — an export that omits a store
  is a wrong answer to a subject's request, and the map is what says which stores exist

## Goal

A tenant can obtain a machine-readable copy of what AGO holds for them — their conversations with
messages and attachment references, their site configuration, their operators — without asking the
author to run a query. Today there is no export of any kind.

## Context to read first

`docs/architecture/personal-data.md` — the same store list `16-02` deletes from, read here as "what
must appear in the file". `docs/architecture/file-storage.md` — attachments are objects, not rows;
whether the export embeds the bytes or presigned links is this item's decision and its main design
question (see Scope). `docs/architecture/data-model.md`'s access strategy and keyset pagination — an
export of a large tenant is a streaming read, not one query into memory, and the existing Dapper
read-store patterns are what it should be built from. `docs/backlog/12-02-cross-tenant-operations-
read-api.md` — the owner-facing read API, deliberately different: that one crosses tenants for the
platform owner, this one stays strictly inside one tenant for that tenant.

## Scope

- An export a tenant triggers from the console, produced asynchronously (same Worker-job shape as
  `16-02`), and made available as a single downloadable archive when ready.
- Contents: conversations, messages with their timestamps and authorship, attachment metadata, site
  configuration, operator list. A documented format — the format is part of the deliverable, since an
  export nobody can read is not an export. **Load-bearing twice over since `adr/0031` (2026-08-25)**:
  the same format is what `13-06` writes as the retention archive, one object per site per period, so
  a later change to it is a change to files already written. Version it, or state why it does not need
  versioning.
- **Attachment bytes: decide and state.** Either included in the archive, which makes it large and
  slow but complete, or referenced by time-limited presigned URLs, which keeps it small but means the
  export decays. Both are defensible; the choice gets written down with its reasoning.
- Streamed, not buffered — a tenant with a year of conversations must not require the API to hold it
  all in memory, and `nfr.md`'s targets are not suspended because an export is running.
- Rate-limited per tenant, using the existing `IRateLimiter` (`3-05`): export is the cheapest way to
  make this deployment do expensive work on demand.
- Authorised by an explicit permission, and scoped so that a tenant can only ever export their own
  data — with a test that proves the second half, since "export" plus a tenancy bug is the worst
  combination in a multi-tenant system.

## Out of scope

- Scheduled or continuous export, an API for it, or any integration shape — nothing asks for it.
- Import, migration in, or restoring from an export.
- Exporting on a visitor's own behalf directly. Visitors have no account (`vision.md`); a visitor's
  request goes to the shop, and the shop uses this. If that ever changes it is a product decision,
  not an extension of this item.
- The platform owner's cross-tenant view — `12-02`.

## Done when

- [x] A tenant can trigger an export and download the result when it is ready — `POST
      /api/v1/sites/{siteId}/exports` (`202`), `GET /api/v1/sites/{siteId}/exports/{exportId}`
      (status/download poll, the same completion-poll shape `16-02`'s `GetConversationByIdHandler`
      established), gated by a new `site:export` permission.
- [x] The archive contains every store `personal-data.md` lists as belonging to that tenant — site,
      operators, visitors, channel identities, conversations, messages, attachment metadata. Two
      stores were deliberately excluded, stated rather than silent: `webhook_deliveries` (body-free by
      contract — operational/integration log about the tenant's own webhook receiver, not conversation
      data, and not named in this item's own Scope enumeration) and `channel_credentials` (holds only
      the tenant's own bot-token/webhook-secret ciphertext — not personal data, and secret-shaped
      besides).
- [x] The format is documented — `adr/0072`, plus `docs/architecture/file-storage.md`'s new section.
      One `.zip` per export, `manifest.json` + one JSON Lines file per store, `formatVersion: 1`.
- [x] The attachment-bytes decision is recorded with its reasoning — `adr/0072`: referenced by
      presigned URL (7-day lifetime, SigV4's own ceiling), not embedded, since `IFileStorage` has no
      byte-returning method and adding one is an `ago-platform` change outside this item's scope.
- [x] The export is streamed and rate-limited — `SiteExportArchiveWriter` reads each store through a
      forward-only `NpgsqlDataReader` straight into the zip, never materializing a `List` of rows;
      `SiteExportRateLimitOptions`/`IRateLimiter` (`3-05`) gate the trigger per site.
- [x] A test proves a tenant cannot export another tenant's data — `SiteExportIntegrationTests`,
      against a real Postgres, and enforced in the query itself (`ExportRequestRepository.GetAsync`'s
      `WHERE id = @id AND site_id = @siteId`), not only in the handler.

## Outcome

Shipped in `ago-chat#113` (merged 2026-08-29; CI green — `build-test` `SUCCESS`). Full command set
green: 0 warnings, 0 errors, 1068/1068 tests across all 6 real `Ago.Chat.*` test assemblies (verified
independently by the managing session after rebasing onto `main`, since `18-07` merged concurrently
mid-task — one additive conflict in `ChatModule.cs`, resolved by keeping both `using` additions).

**Two real gaps found during this queue sweep, neither fixed here, both tracked separately**:

- `ago-deploy/seed/create-demo-tenant.sh`'s Admin role permission array does not grant `site:export`
  — the same pre-existing staleness already present for `16-02`'s `site:erase`/`conversation:erase`,
  in a different repository this item's worker did not touch. Flagged as its own follow-up task.
- **`SiteErasureJob` does not delete a site's export archives.** Verified directly: the `exports/`
  object-storage prefix `SiteExportJob.cs` writes to (`exports/site/{siteId}/{exportId}.zip`) appears
  nowhere else in the codebase except that one writer and one test — no erasure path references it.
  A site erased under `16-02` leaves any export archives it ever produced behind in MinIO indefinitely.
  This is a real hole in `16-02`'s own erasure guarantee, discovered because `16-03` created the first
  data this codebase writes to object storage outside the attachment/thumbnail paths `16-02`'s erasure
  already knows to reach. Flagged as its own follow-up task rather than fixed inline here, since it is
  a `SiteErasureJob` change (a different item's code) and deserves its own verification pass, not a
  drive-by edit in a documentation change.

## Open questions

None.
