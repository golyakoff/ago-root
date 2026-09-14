# ADR-0174: Download overage is invoiced from the proxy meter, under an owner-set monthly cap

- **Status**: Accepted
- **Date**: 2026-09-14
- **Stage**: 25
- **Item**: `25-84` (the paid escape hatch past `25-83`'s hard download block)
- **Relates to**: `adr/0171` (`25-83`'s exemption-versus-block read ordering), `25-43`'s price catalog

## Context

`23-82` built a per-tenant, per-month egress counter and said plainly what it is: a proxy. A presigned
download URL is counted when it is *issued*, so a browser replaying the same URL inside its own TTL is
never re-counted, and `site_attachment_egress.bytes_out` undercounts real egress. That was fine while
the number was only ever *shown* to a tenant.

`25-83` then made a real refusal depend on it. `25-84` makes real money depend on it — 100 ₽ per
gigabyte over the hard threshold — and that is a different question, because a tenant can dispute an
invoice in a way they cannot dispute a dashboard.

The item raised two decisions explicitly and refused to let either be defaulted silently:

1. Is the invoiced figure the raw proxy count, or something reconciled against the storage provider's
   own egress bill?
2. Does auto-bill — which by design has no stopping point mid-month — need a second, higher ceiling
   that even auto-bill cannot cross?

## Decision 1 — the raw proxy count, disclosed, and not reconciled

**The invoiced figure is `site_attachment_egress.bytes_out`, AGO's own measurement, taken when a
download URL is issued.**

The decisive fact is not tolerance for imprecision. It is that **the provider's figure does not exist
at the granularity a tenant would be billed at.** Yandex Object Storage bills egress per bucket, and
this deployment has exactly one bucket shared by every tenant (`docs/architecture/file-storage.md`:
"one list, for every bucket the server holds, which is exactly one here"). There is no provider-side
per-tenant number to reconcile against. The best a reconciliation could do is compute a deployment-wide
ratio between the proxy total and the real bill and scale every tenant's figure by it — which makes one
tenant's invoice depend on other tenants' browser-cache behaviour. That is both less defensible to the
tenant being charged and harder to explain than the undercount it would replace.

Two supporting reasons, neither of them sufficient alone:

- **The error direction is already in the tenant's favour.** The proxy undercounts, so a tenant is
  charged for less than they actually used. A customer does not open a dispute because they were
  undercharged, and the direction is structurally stable rather than incidental — every uncounted event
  is a cache hit, and a cache hit can only ever be an event we failed to count, never one we invented.
- **Building an exact per-tenant counter is a different item.** It would mean proxying the bytes
  themselves through the API, which `docs/architecture/file-storage.md` rules out on purpose ("bytes
  never pass through the API"), or a per-tenant bucket, which is a storage-layout change with its own
  cost.

**The obligation this takes on is disclosure, not accuracy.** The tenant-facing figure and the charge
are the same number, and the proxy nature is stated in `docs/architecture/data-model.md` where the
table is defined, in `IAttachmentEgressMeter`'s own remarks, and in the runbook a platform owner reads
before changing a price. A number a tenant is charged from must be one AGO can explain; this one is.

### Rejected: reconcile against the provider's bill

Rejected for the attribution reason above. If this deployment ever moves to a bucket per tenant, the
question genuinely reopens — at that point a real per-tenant provider figure exists, and the honest
thing would be to bill from it.

## Decision 2 — yes, a cap, owner-configurable per tier

**`tier_download_thresholds.auto_bill_cap_rub`: the most a site on that tier may accrue in
download-overage charges within one calendar month before `25-83`'s block returns, despite auto-bill.
`NULL` means uncapped, which is available to the platform owner but is not the shipped default.**

Every other charge AGO Chat makes is initiated by the tenant: they choose a seat count, they buy an
Administrator slot. This one is driven by **third parties** — the tenant's own visitors clicking
download links. An unbounded charge produced by somebody else's behaviour is the shape that ends in a
chargeback and a refund rather than revenue, and the tenant who says "I did nothing" is factually
correct.

The asymmetry settles it. With no cap, the ceiling on one month's damage is whatever a script can
fetch. With a cap, the worst case is a tenant blocked at a number the platform owner chose — a state
this product already implements end to end, because `25-83` built exactly it, and one the owner can
lift with a single write.

**Per tier, unlike the price.** The item left the price deployment-wide unless argued otherwise, and
that is right: a gigabyte costs what a gigabyte costs regardless of who downloaded it. A cap is the
opposite kind of number — a judgement about how much exposure a *kind* of customer should be allowed —
and a free-tier tenant who has never paid anything is not the same judgement as a Business tenant on a
real subscription. So it lives in the per-tier table `25-83` already built for per-tier download
policy, edited by the runbook that already edits that table.

**The cap applies to a manual tenant too, once they have paid.** The question was asked about auto-bill,
but after a manual checkout the tenant is in the identical situation the question is about — accruing
without acting — so one rule covers both.

### Rejected: no cap at all

Rejected because the exposure is unbounded and is created by people the tenant does not control. "That
is the whole point of unblocked" is true of a month, not of a month with no ceiling.

### Rejected: a cap in bytes rather than roubles

Rejected because the thing anyone is actually afraid of is a large bill, and a byte cap expresses it
only indirectly — it would silently change meaning the moment the owner republishes the price.

## Consequences

- A tenant can be blocked in a state no purchase lifts (at the cap). The console says so explicitly
  rather than offering a button the server would refuse.
- Auto-bill requires an active subscription to settle onto, so the free tier's cap ships at `0.00` —
  stating as data that auto-bill cannot function there. A free-tier tenant's real route past the block
  is the manual checkout, which needs no stored payment method.
- The invoiced figure remains an undercount, permanently and by design. Anyone later tempted to
  "fix" it should read the attribution argument above first: the fix is a bucket per tenant, not a
  reconciliation.
