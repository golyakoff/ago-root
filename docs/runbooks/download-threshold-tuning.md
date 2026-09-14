# Tuning a tenant's download-cap thresholds

`25-83`, 2026-09-14; extended by `25-84` the same day with the auto-bill cap and the per-gigabyte
overage price. Two things a platform owner can adjust for the download-cap mechanism
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
SELECT tier, soft_threshold_bytes, hard_threshold_bytes, auto_bill_cap_rub, updated_at, updated_by
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

## The auto-bill cap, and the per-gigabyte overage price

`25-84`. Two more numbers the platform owner sets, and they live in two different places for a reason
worth stating rather than discovering.

### `tier_download_thresholds.auto_bill_cap_rub` — per tier, here

The most a site on this tier may accrue in download-overage charges within one calendar month before
the `25-83` block returns *despite* the tenant being on auto-bill (or having paid their way past the
block earlier in the month). `NULL` means uncapped.

Per tier rather than deployment-wide because a cap is a judgement about how much exposure a kind of
customer should be allowed, and a free-tier tenant who has never paid anything and a Business tenant on
a real subscription are not the same judgement.

```sql
UPDATE tier_download_thresholds
SET auto_bill_cap_rub = <roubles, or NULL for uncapped>,
    updated_at = now(),
    updated_by = '<your own identifier>'
WHERE tier = '<tier>';
```

The shipped values are a **labelled starting point, not a measured figure** (the same posture the two
thresholds themselves take): `starter` = 1000.00, rounded up from the 890 RUB/month this tier's own
maximum seat configuration costs, so auto-bill can at most roughly double what a tenant already agreed
to pay; `free` = 0.00, which states as data the fact that auto-bill cannot function on the free tier at
all — it settles onto a renewal charge, and a free-tier site has no subscription and no stored payment
method for one to land on.

### The per-gigabyte price — **not here**, in the price catalog

`100.00 RUB` per gigabyte over the hard threshold, shipped as `v1` of the `download-overage-per-gb`
price key. **Do not edit this with SQL.** It is owner-published data with a real write path and a real
version history (`25-43`): publish a new version from the owner console's own pricing screen, which
lists this key alongside the seat prices because `PricedResourceKeys.All` registers it. Editing
`published_price_versions` by hand would break the grandfathering every charge row depends on —
`download_overage_charges.price_version` names the exact version an amount was computed from, and a
tenant disputing an invoice line is answered from that row.

A gigabyte here is **1024³ bytes**, matching the binary thresholds it is measured against — not the
decimal gigabyte the storage provider prices in.

### Which mode a tenant is on

`POST /api/v1/owner/sites/{siteId}/download-overage-billing-mode`, gated by `RequirePlatformOwner`,
the same shape as the exemption route above:

```
{ "mode": "AutoBill" | "Manual", "reason": "<why — required, both directions>" }
```

Every site starts on `Manual`, which is exactly `25-83`'s own behaviour: blocked at the hard threshold
until the tenant completes a real checkout. `AutoBill` is the recommended setting but is never applied
by a migration — moving a tenant onto it starts charging them, and that is a decision somebody makes
for a named account with a stated reason, not a default that arrives with a deploy.

## What this does not cover

Changing a threshold or granting an exemption never touches `site_attachment_egress.bytes_out` — the
tenant's own already-measured usage this month. It only changes what that figure is compared against
(the threshold) or whether it is compared at all (the exemption). A tenant who is already blocked stays
blocked until the next presigned-download request re-reads the new threshold or the new exemption flag
— there is no cache to invalidate, but there is also no way to retroactively un-refuse a request that
already failed before the change landed.

Nor does any of it settle an *already accrued* charge: `download_overage_charges` is append-only, and
lowering a price or raising a cap changes only what is computed from the next request onwards. A row
already written names the price version it was computed at, deliberately.
