# Export: a tenant can take their data out

- **Stage**: 16
- **Status**: ready
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

- [ ] A tenant can trigger an export and download the result when it is ready.
- [ ] The archive contains every store `personal-data.md` lists as belonging to that tenant.
- [ ] The format is documented.
- [ ] The attachment-bytes decision is recorded with its reasoning.
- [ ] The export is streamed and rate-limited.
- [ ] A test proves a tenant cannot export another tenant's data.

## Open questions

None.
