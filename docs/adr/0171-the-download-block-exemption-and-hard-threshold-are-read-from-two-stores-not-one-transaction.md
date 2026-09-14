# ADR-0171: The download-block exemption and the hard threshold are read from two stores, not one transaction

- **Status**: Accepted
- **Date**: 2026-09-14
- **Stage**: 25

## Context

`25-83` gates every presigned attachment download behind two live facts, read on every request inside
`GetAttachmentDownloadUrlHandler.EnforceDownloadCapAsync`:

1. **`Site.DownloadBlockExempt`** — the platform owner's own free, indefinite bypass, written through
   `AgoChatDbContext` (`SetDownloadBlockExemptionAsOwnerHandler`, an ordinary EF-tracked aggregate
   save).
2. **The tenant's current-month egress**, against its tier's hard threshold — read through
   `IAttachmentEgressReadStore`, a Dapper read store backed by raw `NpgsqlDataSource` connections
   (`23-82`'s own precedent: `site_attachment_egress` has no EF entity at all, by design —
   `data-model.md`'s own remarks).

Both reads must be live and uncached (CLAUDE.md rule 8: a compare-and-set-adjacent read a write
decision depends on comes from the database, not a cache) — that part was never in question. What
needed a decision is *how* the two reads relate to each other when an owner's grant and a tenant's
request land in the same narrow window: does a request that arrives the instant before the owner's
`POST` commits see the world before the grant, or can it observe a torn, half-updated state — or worse,
slip through as allowed when it should still be refused?

`EF Core` (`AgoChatDbContext`) and the raw `NpgsqlDataSource` the Dapper read store opens its own
connection from are, structurally, two different connections. There is no single `BEGIN` that could
wrap both reads together without either moving the exemption flag out of `AgoChatDbContext` (so it
could be read on the egress store's own connection) or moving the egress read into `AgoChatDbContext`
(so it could join a transaction with `Site`) — and `23-82` already decided, for its own reasons, that
`site_attachment_egress` has no EF entity.

## Decision

**Read the exemption flag first. Read the egress figure only if the flag says not exempt.** Both
reads are live, on every call, with no caching of either — but they are two separate reads against two
separate connections, not one atomic snapshot.

The accepted consequence: a request that reads `DownloadBlockExempt = false` a moment before the
owner's grant commits is refused once, incorrectly — and succeeds on an immediate retry, once the flag
has actually changed. The reverse ordering (read the egress figure first, decide "over the hard
threshold," then check the flag) is deliberately *not* what this handler does, because it opens the
opposite window: a request that reads a stale "not yet exempt" moment before a **revocation** commits
would need the flag re-checked afterward anyway to still refuse correctly, and a request racing a
*grant* the other way could slip through as allowed a moment before the flag says so — an actual bypass
of an owner-controlled security decision, not merely a wrongly-refused retry.

Put plainly: this ordering trades an occasional false refusal (safe direction — costs the caller one
retry) for never trading a false allow (unsafe direction — an unauthorized download would already have
happened, and cannot be un-issued after the fact).

## Consequences

**Positive**: no new cross-store transaction, no new coordination primitive, and no widening of either
store's own responsibility (the exemption flag stays a plain `Site` scalar; the egress figure stays
Dapper-only, exactly as `23-82` already decided). The race window is narrow — the width of two
sequential round-trips inside one request — and its only externally visible effect is one retried
request, never a wrong grant of access.

**Negative**: this is a real, accepted race, not a closed one. A tenant whose owner grants an exemption
in the same instant a blocked download is retried may see one extra `403` before the retry succeeds.
That is a worse experience than a perfectly atomic read would give, and this ADR is explicit that the
false-refusal case exists and is intentional, rather than an oversight a future reader might otherwise
"fix" by reordering the two checks — which would reintroduce the unsafe direction this decision
exists to avoid.

## Alternatives considered

**Move `DownloadBlockExempt` into the Dapper-only egress store**, so both facts come off the identical
connection inside one query. Rejected: the exemption flag is a genuine `Site` aggregate concern (it has
its own audit trail — who granted it, when, why — the same shape every other owner-only override on
`Site` already carries) and moving it out from under `AgoChatDbContext` would strip it of that context
for no benefit beyond closing a window whose unsafe direction is already closed by the read ordering
above.

**Move the egress read into `AgoChatDbContext`**, joining a real EF transaction with `Site`. Rejected
for the identical reason `23-82` already gave for keeping `site_attachment_egress` out of EF entirely:
no domain invariant lives on that table, its only writer is a raw upsert with no ambient transaction to
join in the first place (`AttachmentEgressMeterStore`'s own remarks), and folding a high-write-volume
counter into the aggregate's own DbContext would be a larger, unrelated change to buy a narrower race
window that the read-ordering decision above already makes safe in the direction that matters.

**A single cross-store snapshot via a serializable transaction or an application-level lock.** Rejected
as disproportionate: the only consequence of the accepted race is one retried request, on an act (an
owner manually flipping a rarely-changed exemption flag) that is not itself a hot path. Building
cross-store coordination to close a window whose worst case is "try again" is exactly the kind of
premature generalisation `clean-architecture.md` warns a platform-shaped fix against, for a
product-layer problem this narrow.
