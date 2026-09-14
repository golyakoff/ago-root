# 25-83 · A tenant that downloads too much is warned, then blocked

- **Stage**: 25
- **Status**: ready
- **Depends on**: `23-82` (done, `ago-chat#288`/`ago-console#225`) — the egress counter this item
  enforces against already exists and is live.
- **Decision**: the author's, reached in dialogue with the managing session, 2026-09-14 — see below
  for the full shape. This item is the mechanism; `25-84` is the paid escape hatch from it.
- **Found**: `23-82`'s own third Done-when — "whether there is a ceiling, and what happens at it, is
  decided with the tier grid rather than here" — deliberately left open pending this conversation.

## The shape, decided 2026-09-14

**Two planks, per tier, stored in the database.** A soft warning threshold and a hard block
threshold, both configurable per tariff tier by the platform owner — the same "per-tier, not
universal" precedent `23-76`'s own storage quota already set. If no console screen exists yet for
editing them when this ships, the columns still exist and a runbook script edits them by hand — never
a hardcoded constant standing in for a real per-tier table.

**Crossing the soft threshold**: an active notification, not merely a number waiting to be noticed on
`23-80`'s own storage screen — an email, and a console banner that cannot be dismissed, in a warning
tone (yellow/orange) rather than a danger one. The distinction matters: this is "you are approaching
a limit," not "something is broken."

**Crossing the hard threshold**: every presigned GET refuses, for **everyone** — an operator in the
console and a visitor in the widget alike. This was a deliberate, explicit choice against this
codebase's own instinct ("refusing a download is worse than refusing an upload," `23-82`'s own
Scope): a tenant is responsible for their own visitors' experience, the same way they are responsible
for everything else about their own account, and carving out an exception for visitor downloads would
let a tenant's own inattention become a stranger's broken experience with no lever the tenant is ever
forced to notice. **A system message lands directly in the conversation where a visitor's download was
refused** — the one channel most likely to actually reach an operator who missed the console banner,
because they are already looking at that exact conversation when it happens.

**An owner-controlled per-tenant override**: a platform-owner-only toggle, off by default, that lets
a specific tenant's account bypass the hard threshold for free, indefinitely — a manual exception, not
a product feature a tenant can reach themselves. Reuses the same "the owner sees and can grant an
exception" shape `23-85`'s/`25-76`'s own owner-only routes already established.

**What happens at the hard threshold beyond the block itself — the paid path to lift it — is `25-84`'s
own scope, not this item's.** This item's own Done-when is satisfied by a blocked tenant with no way
to self-unblock except the owner's manual override above; `25-84` is what gives them a self-service
one.

## Where this is likely to go wrong

- **The egress counter this enforces against is a stated proxy, not an exact figure** (`23-82`'s own
  `IAttachmentEgressMeter` remarks: a cache hit inside a presigned URL's own TTL is never re-counted,
  so the count undercounts real egress). That was an acceptable proxy for "roughly gauge whether a
  ceiling makes sense" — it is a different question whether it is precise enough to gate a real
  refusal. Undercounting errs in the tenant's favor (they get blocked later than a perfectly accurate
  count would), which is the safe direction, but say so explicitly in this item's own report rather
  than silently inheriting `23-82`'s own caveat as if it were still just an observability footnote.
- **The in-conversation system message needs a locale.** `RouteConversationToModuleHandler`'s own
  four texts (`25-64`/`25-66`) are the precedent — Russian on a `Locale.Ru` site, English otherwise,
  not a fifth hardcoded-English string shipped the night after the last four were fixed.
- **The owner's override toggle and the hard block must not race.** A tenant crossing the threshold in
  the same window the owner flips the override needs a defined ordering (read-then-decide inside one
  transaction, not a stale in-memory read of the toggle from before the flip).

## Out of scope

- The paid overage entitlement, its price, its checkout flow, and the owner's "auto-bill vs. tenant
  must pay explicitly" toggle — all `25-84`.
- Any tenant-facing self-service control over either threshold or the override — both stay the
  platform owner's alone, per the decision above.

## Done when

- [ ] Both thresholds exist per tariff tier in the database, editable by the platform owner (a
      console screen if one ships with this item, a runbook script otherwise) — never a single
      universal constant.
- [ ] Crossing the soft threshold sends an email and shows a non-dismissable, warning-toned console
      banner, proven against a real tenant crossing it.
- [ ] Crossing the hard threshold refuses every presigned GET — operator and visitor alike — proven
      by fault injection for both callers.
- [ ] A visitor's refused download drops a locale-aware system message into that exact conversation.
- [ ] The platform owner can grant a specific tenant a free, indefinite override, off by default,
      proven to actually bypass the hard block once granted.
- [ ] The egress figure this enforces against is stated, in this item's own report and in
      `docs/architecture/file-storage.md` or `caching.md` (whichever already carries `23-82`'s own
      caveat), as a proxy that undercounts — not silently treated as exact now that real refusals (and
      `25-84`'s own real money) depend on it.
