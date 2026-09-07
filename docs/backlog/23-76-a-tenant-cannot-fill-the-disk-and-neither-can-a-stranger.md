# a tenant cannot fill the disk, and neither can a stranger

- **Stage**: 23
- **Status**: ready — **and the first question in it is the one that matters**
- **Depends on**: `23-75` is the per-conversation budget. This is the part that actually bounds storage.
- **Found**: 2026-09-07, asked by the author: *«файлы — самое опасное, как не дать засрать весь MinIO».*

## The thing worth saying first

**A per-conversation budget does not protect storage at all.**

A visitor token is free to obtain — that is the design, and it should stay that way. So an attacker who
has spent one conversation's 100 MB opens another and gets a fresh 100 MB. The per-conversation limit
protects a *conversation*: the operator's screen, the tenant's own sanity, the download a colleague has
to wait for. It bounds nothing globally, and believing otherwise is the failure this item exists to
prevent.

What bounds storage is a ceiling on the thing an attacker cannot mint for free: **the tenant.** Every
abusive upload happens through some tenant's widget, and the tenant is the account with a tier, a
payment and a quota.

## What exists today

- Per-file: 10 MB, enforced twice (`5-13`).
- Rate limits per site, per visitor, per operator (`AttachmentRateLimitOptions`) — **counts, not bytes**.
- An allowlist of content types: images and PDF only. That already excludes the "store an executable"
  class of abuse, and is worth knowing before anybody proposes a virus scanner.
- **No per-tenant storage total. No bucket ceiling. No disk alert that names attachments.**

## Scope, in the order that matters

1. **A per-tenant storage quota, by tier.** The number belongs to the tier grid, not here. Free is
   already bounded in one direction by the two-month retention window (`23-74`); this bounds the other.
2. **A rate limit on conversation creation per origin and per address**, because a fresh conversation is
   what resets `23-75`'s budget. Without this, the budget is a speed bump.
3. **A ceiling the application cannot exceed even if it is wrong** — a bucket quota, or attachments on
   their own volume, plus an alert on disk usage. MinIO on this node shares a machine with Postgres and
   Redis; a full disk is not a degraded upload feature, it is an outage of everything.
4. **Make a new conversation cost something, but only under suspicion.** A visitor identity is issued
   instantly and free, which is what makes item 2 a speed bump rather than a limit. The answer is not to
   tax everybody: when one site's upload behaviour is already anomalous, issuing another identity for
   *that site* can cost a delay, a challenge, or a little browser work. An honest visitor notices a
   second; a script that needs two hundred identities does not get them.
5. **Deduplicate by content hash.** An attacker uploading the same 10 MB two hundred times should cost
   one object. This is cheap, it is invisible to honest users, and it defeats the naive flood outright
   — which is most of them.

## The question the author asked, answered honestly

*What is in the assortment for an attack analyser?*

**Quotas make an attack boring; detection is for what quotas miss.** An anomaly detector built before
the ceilings exist would spend its life reporting things we chose not to prevent, and somebody would
have to read those reports.

So detection is item 6, not item 1, and it should be narrow: **the upload rate for one site jumping far
above that site's own history**, which is a signal that a *tenant is being abused* rather than that a
tenant is abusing. The useful response is to throttle that site and tell somebody — not to guess intent.

Two things explicitly rejected rather than deferred:

- **Content inspection for "attack" payloads.** The allowlist is images and PDF; the risk that remains
  is volume, not content. A scanner would be answering a question nobody asked.
- **Per-visitor reputation.** A visitor is anonymous and free to recreate, so reputation attaches to
  nothing. Any effort here is better spent on the tenant ceiling.
- **Blocking or rate-limiting by IP address.** Rejected outright, and written down because it will be
  proposed again. It is wrong **in both directions**: too coarse to be safe, because most traffic here
  arrives through a VPN exit shared by thousands of unrelated people, and too cheap to evade to be
  effective, because the one person it was aimed at changes exit for pennies. It punishes the innocent
  reliably and the guilty barely. An address is captured today as evidence in consent and acceptance
  records and constrains nothing anywhere, which is the right place to leave it.

## What `23-78` changes about all of this

The author proposed, the same day, that a visitor gets no upload control at all until an operator
agrees in that conversation. **That removes the vector these items bound**, and it is cheaper than any
of them.

Nothing here should be dropped on the strength of it. A control that depends on a person can be talked
around one conversation at a time; a quota cannot. But the ordering changes: after `23-78`, the ceilings
are for an operator who granted permission to somebody abusive and for a tenant abusing their own
account — not for the anonymous flood.

## Where this is likely to go wrong

- **A quota that refuses uploads for a paying tenant because a stranger filled it is a hostage
  situation.** Decide what a tenant sees and can do when their own quota is exhausted by abuse, before
  the quota exists. This is the part most likely to be discovered by a customer.
- **Deduplication and erasure interact.** If two tenants share one object, deleting one tenant's
  attachment must not delete the other's. `adr/0108` already rewrites rather than deletes an archived
  object; check that reasoning before sharing anything across tenants — the safe first version
  deduplicates **within** a tenant only.

## Done when

- [ ] A tenant's total attachment storage is bounded, by tier, and the bound is enforced at presign.
- [ ] Creating conversations at speed does not multiply the available budget.
- [ ] There is a ceiling below which the disk cannot be filled by this feature, and an alert before it.
- [ ] The same bytes uploaded repeatedly cost one object, within a tenant.
- [ ] What a tenant sees when their quota is exhausted is decided rather than discovered.
