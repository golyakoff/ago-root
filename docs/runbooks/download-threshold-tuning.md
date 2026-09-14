# Tuning a tenant's download-cap thresholds

`25-83`, 2026-09-14. Two things a platform owner can adjust for the download-cap mechanism
(`docs/backlog/25-83-*.md`): the two per-tariff-tier byte thresholds that decide when a tenant is
warned and when it is blocked, and one specific tenant's own free, indefinite exemption from the block.
Only the second has a console screen or an API route yet — this page is the whole procedure for the
first, and the fallback for the second.

## The two thresholds are per tier, not per tenant

Every tenant on the same tariff tier (`free`, `starter`, …) shares the same soft (warn) and hard
(block) threshold — `Ago.Chat.Application.Abstractions.IDownloadThresholdReadStore` reads them from
`tier_download_thresholds`, keyed by `tier` alone. There is no console screen for this table yet
(`docs/backlog/25-83-*.md`'s own Scope: it shipped with a runbook script instead), so this page **is**
the ordinary route, not a fallback — the opposite of `module-grant-and-revoke.md`'s own situation.

**Read the current values:**

```sql
SELECT tier, soft_threshold_bytes, hard_threshold_bytes, updated_at, updated_by
FROM tier_download_thresholds
ORDER BY tier;
```

**Change one tier's thresholds** — `hard_threshold_bytes` must stay strictly greater than
`soft_threshold_bytes` (a database check constraint enforces this; a violating `UPDATE` is refused,
not silently accepted):

```sql
UPDATE tier_download_thresholds
SET soft_threshold_bytes = <bytes>,
    hard_threshold_bytes = <bytes>,
    updated_at = now(),
    updated_by = '<your own identifier — an email or a ticket reference, not "admin">'
WHERE tier = '<tier>';
```

**Add a threshold for a tier that has none yet.** A tier with no row here is never blocked — every
download succeeds regardless of usage, and the soft-threshold sweep never produces a warning for it
either (`IDownloadThresholdReadStore`'s own remarks: a missing row fails open, on purpose, so a
configuration gap does not turn into an outage the moment a new tier is created). If a tenant on a new
tier should actually be capped, insert a row:

```sql
INSERT INTO tier_download_thresholds (tier, soft_threshold_bytes, hard_threshold_bytes, updated_at, updated_by)
VALUES ('<tier>', <soft bytes>, <hard bytes>, now(), '<your own identifier>');
```

There is nothing to restart or invalidate afterward — `GetAttachmentDownloadUrlHandler` reads this
table live, uncached, on every download request (CLAUDE.md rule 8), so a change here takes effect on
the very next request against that tier.

## One tenant's own exemption from the hard block

Unlike the thresholds above, this has a real API — `POST /api/v1/owner/sites/{siteId}/download-block-exemption`
(`Ago.Chat.Api.Owner.OwnerDownloadBlockExemptionEndpoints`), gated by `RequirePlatformOwner`, the
identical shape `module-grant-and-revoke.md`'s own two routes already have. Use it in the ordinary
case; the direct SQL below is the fallback, for the day the API is unreachable.

```
POST /api/v1/owner/sites/{siteId}/download-block-exemption
{ "exempt": true, "reason": "<why — required, both directions>" }
```

`exempt: false` on the identical route revokes it. A reason is required either way — this is a
free, indefinite bypass of a real enforcement mechanism, and `Site.DownloadBlockExemptionChangedBy`/
`DownloadBlockExemptionReason`/`DownloadBlockExemptionChangedAt` are the only record of who granted
it and why (`Site.GrantDownloadBlockExemption`'s own remarks on why this is a single current-value
audit trail, not a full ledger).

**The fallback, direct against the row** (only if the API is genuinely unreachable):

```sql
UPDATE sites
SET download_block_exempt = true,
    download_block_exemption_changed_by = '<your own identifier>',
    download_block_exemption_reason = '<why>',
    download_block_exemption_changed_at = now()
WHERE id = '<siteId>';
```

## What this does not cover

Changing a threshold or granting an exemption never touches `site_attachment_egress.bytes_out` — the
tenant's own already-measured usage this month. It only changes what that figure is compared against
(the threshold) or whether it is compared at all (the exemption). A tenant who is already blocked stays
blocked until the next presigned-download request re-reads the new threshold or the new exemption flag
— there is no cache to invalidate, but there is also no way to retroactively un-refuse a request that
already failed before the change landed.
