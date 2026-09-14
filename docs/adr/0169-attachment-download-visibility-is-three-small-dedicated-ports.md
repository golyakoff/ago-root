# ADR-0169: Attachment download-visibility is three small dedicated ports, not a widened budget port

- **Status**: Accepted
- **Date**: 2026-09-14
- **Stage**: 23

## Context

`23-76` gave every tenant a storage ceiling, enforced by `ISiteAttachmentStorageBudget` -
`TryReserveAsync`/`ReleaseAsync`, a compare-and-set read-then-write inside the same transaction as the
upload it gates (CLAUDE.md rule 8: a write decision's own read never comes from anywhere else).

`23-82` and `23-80` were found while pricing that ceiling rather than while reading code: storage is
cheap (2,376 ₽/GB/month on Yandex Object Storage) and egress is not (1,68 ₽/GB, so a gigabyte costs
about as much to keep for a month as to download one and a half times), and nothing counted downloads
at all - a quota bounding storage says nothing about the same 100 MB being fetched a thousand times.
Alongside that, `23-80`'s own console screen needed to show a tenant what they hold: every attachment,
sortable by size/type/age/conversation/sender, with a "never downloaded" and a "duplicate by content
hash" filter, and a bulk-delete that leaves an honest transcript rather than a broken link.

None of what these two items need is a write decision the way `23-76`'s reservation is. They need:
a maintained per-tenant-per-month egress aggregate, written after the fact rather than gating anything;
a bare read of the byte total `23-76` already reserves, so the console figure agrees with enforcement
by construction rather than by a second computation; a sortable/filterable list read, including
"duplicate" and "never downloaded" predicates; and a way for a resolved attachment to say it was
deleted, on the same hot read (`GetConversationHistory`) that renders every message a tenant has ever
sent.

## Decision

Three new, narrow ports in `Application/Abstractions`, alongside `ISiteAttachmentStorageBudget` rather
than folded into it:

- **`IAttachmentEgressMeter`** - the write half of a maintained aggregate (`site_attachment_egress`,
  keyed `site_id`/`period_month`). `RecordAsync(siteId, periodMonth, bytes, ct)` is called by
  `GetAttachmentDownloadUrlHandler` only when it mints a *fresh* presigned URL - a cache hit within
  that URL's own TTL is not re-counted, and this is stated on the port itself as a caveat every caller
  must carry forward: the number is a proxy for real egress, and the storage provider's own bill is
  the one true figure.
- **`IAttachmentEgressReadStore`** - the read half of that same aggregate, for the console screen and
  for AGO's own visibility. `GetForSiteAsync` returns a real, explicit zero (never a missing row) when
  nothing has been recorded yet - "no evidence" and "measured zero" are the same fact for a tenant
  nobody has downloaded from.
- **`IAttachmentBudgetReadStore`** - a bare read of `sites.attachment_bytes_reserved`, the exact
  column `ISiteAttachmentStorageBudget`'s own `TryReserveAsync`/`ReleaseAsync` already maintains.
  `GetReservedBytesAsync` does not recompute the total by summing attachment rows; it reads the one
  maintained column, so "the console figure agrees with what enforcement believes" is true by
  construction rather than by keeping two computations in sync.

`site_attachment_egress` gets no EF entity - a raw upsert on write, a Dapper read on read, the same
"writes and reads both bypass the change tracker" shape `23-76`'s own `attachment_bytes_reserved`
column already uses (`adr/0004`).

A resolved-but-deleted attachment gets a new, distinct, permanent error code, `Attachment.Removed`
(HTTP `410 Gone`, `ConversationErrors.AttachmentRemoved`), returned by `GetAttachmentDownloadUrlHandler`
before the existing `Attachment.NotReady` check - deliberately a different code from `NotReady`, which
also covers a merely-still-uploading attachment: one is permanent, the other is retryable, and a caller
must be able to tell them apart.

"Is this attachment a duplicate" is answered by a per-row `EXISTS` against `23-76`'s own partial index
(`ix_attachments_site_content_hash`, filtered `state = 'Ready' AND content_hash IS NOT NULL`), computed
per row in `SiteAttachmentListReadStore`, not a window function over the tenant's whole `Ready` set.

## Consequences

- Enforcement (`ISiteAttachmentStorageBudget`) stays exactly what it was: a write-gate with one job,
  untouched by this change and safe to reason about in isolation.
- Three small ports instead of one wider one means three things to register and three fakes to write
  in tests, rather than one interface growing methods that do not share its transactional contract.
  The cost is more files; the benefit is that nothing reading `ISiteAttachmentStorageBudget` has to
  wonder whether a given method is safe to call outside a reservation transaction.
- The egress figure is explicitly a proxy, forever - a cache hit inside a presigned URL's TTL is
  invisible to it, and a browser replaying a cached URL is invisible to it too. Anyone consuming
  `IAttachmentEgressReadStore` inherits that caveat and must not present the number as ground truth.
  (`adr/0171` later reads this same store, read-only, to enforce a download cap - a second consumer
  that had to inherit the identical caveat rather than rediscover it.)
- `Attachment.Removed` is one more permanent error code a client must map, distinct from `NotReady`.
  The alternative it replaces (see below) would have added a per-read cost to the busiest query in the
  product instead.
- Two gaps were found while building this and deliberately not fixed here, because fixing them was out
  of this item's own scope: `5-08`'s pre-existing single-attachment delete path was found not to
  release this same budget reservation at all (filed as `25-79`, since fixed - `fdaffbb`); `ago-widget`
  does not yet know the `Attachment.Removed` code, a named, non-regressing residual (`25-80`).

## Alternatives considered

- **Widen `ISiteAttachmentStorageBudget` with the new reads and the meter.** Rejected: it blurs a
  write-gate a transaction depends on with pure observability. A reader of that interface today has to
  know every method is safe to call mid-reservation; adding read-only, non-transactional methods to it
  would make that no longer true, for no benefit - the new methods share no contract with the existing
  two.
- **Join `messages` against `attachments` to detect a deleted attachment, instead of a distinct error
  code.** Rejected: `GetConversationHistory` is, by its own doc comment, "the hottest read in the
  product." Adding a join there to surface one rare state (an attachment removed after the message was
  sent) is an unmeasured cost paid on every history read for every conversation, forever, to serve a
  case that is otherwise resolved for free by the download endpoint returning a distinct, cacheable
  status code the one time someone actually tries to fetch the file.
- **A window function over the tenant's whole `Ready` attachment set, to compute "duplicate" once per
  page.** Rejected on the same shape of cost: it pays for scanning every row the tenant holds on every
  page load of the storage screen, where a per-row `EXISTS` against an existing partial index costs
  only what the current page actually renders.
