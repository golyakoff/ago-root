# the platform owner cannot grant a product to a tenant

- **Stage**: 22
- **Status**: done — merged 2026-09-04 (`ago-calendar#38`, `ago-chat#166`); `adr/0098`
- **Found**: 2026-09-04, raised by the author after finding they could not reach a calendar screen
  with their own account and that the only workaround on offer was *register a new site*.

## What exists, and what does not

`EnableModuleForSite` and its endpoint exist (`19-03`), gated on `RequireOperatorIdentity` — **the
tenant switches a module on for itself**. `22-07` designs that path fully: a feature list on the
tenant's own settings screen, a master count, payment through YooKassa.

The platform owner has no part in it. `/api/v1/owner/` today can list sites and act on channel
identities; nothing grants a product.

That is a coherent design — the product is self-service — and it is incomplete for three reasons,
none hypothetical.

**Sales and trials.** Giving a prospect the calendar for a month without taking money is the ordinary
commercial motion. Today it requires either a real payment or an edit in the database.

**Support.** `22-07` names the worst outcome in its own text: *payment succeeded, provisioning did
not*. Nobody can currently deliver what was paid for — there is no surface for it, so the remedy is
hand-written SQL against a live tenant.

**It has already bitten.** The author cannot see the calendar at all: their account predates `22-05`,
and the only workaround was creating a new tenant in production.

## Why its own number rather than part of `22-07`

Different promise. `22-07` is *a tenant can buy the calendar add-on and gets a quota with it*; this is
*the platform owner can grant a product to a tenant without a payment*. Each lands green on its own,
and either can ship first.

**It should probably ship first.** It is much the cheaper of the two — no payment path, no quota
ladder, no tier interaction — and it is what lets a first client be given the calendar at all.

## What has to be got right rather than defaulted

- **This is a deliberate cross-tenant write**, exactly the category `12-02`/`adr/0032` and `17-01` were
  careful about. An owner writing into a tenant's entitlements must be distinguishable in the record
  from a tenant doing it — otherwise nobody can tell "we granted this" from "they bought it".
- **It must not become the normal path.** Self-service is the product; this is the exception for sales
  and repair. If it is easier than paying, it will be used instead of paying.
- **The grant still crosses products.** Chat grants, the calendar holds and enforces (`22-07`'s own
  reasoning, rule 8): the granted state lives in the calendar's own database and propagates over the
  outbox, never a cross-product read on a write path.
- **A grant with no expiry is a discount nobody remembers giving.** A trial that never ends is the
  failure mode; decide whether a grant carries an end date rather than discovering it in a year.

## Done when

- [x] A platform owner can enable a product for a named tenant, and that tenant can then use it —
      proven end to end, by a call that failed before and succeeds after.
- [x] The grant is distinguishable from a purchase wherever either is recorded.
- [x] Revoking it works and is proven by trying it, not asserted — an entitlement that cannot be taken
      back is not an entitlement.
- [x] Chat still does not learn the word "calendar" (`adr/0093`): it grants a **module**.

## Outcome

`PUT`/`DELETE /api/v1/owner/sites/{siteId}/modules`, gated by `RequirePlatformOwner` and nothing else,
reaching the identical `EnabledModule` aggregate and the identical `22-11` registration mechanism the
tenant's own self-service route uses — **a second caller, not a second mechanism**. `GrantedByOwner`
and `ExpiresAt` sit on the entitlement row itself, so a grant and a purchase are the same record with
different values rather than two records free to disagree. `ExpiresAt` is `required` and nullable: a
perpetual grant is allowed and must be stated. `adr/0098` carries the reasoning.

**Three things this delivered that the item did not ask for, and one it asked for and did not get.**

The calendar had no way to hold a tenant it had never seen, so `RegisterChatModuleHandler` now
auto-provisions one. That **widened the provisioning secret's blast radius past the enumeration
`adr/0095` had made checkable** — a holder can now create accounts, unbounded — which is amended into
that ADR rather than absorbed, and marked in the data by `Tenant.AutoProvisioned` and a separate
factory. `22-18` remains what ends the exposure.

Two documents were false and are corrected here: `authorization.md` and `tenant-isolation.md` both
said no platform-owner write surface existed anywhere, which had been untrue since `14-12`'s owner
unlink and is now untrue three times over.

**"Revoking it works" is true only on the granting side.** Chat stops offering an expired module
immediately; the calendar is never told a grant lapsed and will still serve a call whose assertion it
can verify. An explicit revoke reaches both sides; an expiry does not. Stated in `adr/0098` rather
than left to be found.
