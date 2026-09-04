# ADR-0098: An owner's grant is recorded on the entitlement itself, and expires only on the granting side

- **Status**: Accepted
- **Date**: 2026-09-04
- **Stage**: 22

## Context

`19-03` gave a tenant one way to switch a module on: `EnableModuleForSite`, gated on
`RequireOperatorIdentity` plus `site:configure`. Self-service is the product, and `22-07` designs the
paid version of that same path — a feature list, a master count, payment through ЮKassa.

Three ordinary commercial motions have no path at all through it, and none of the three is
hypothetical (`backlog/22-17`):

- **A trial without payment.** Giving a prospect the calendar for a month is how software is sold.
  Today it requires either a real payment or an edit against a live database.
- **A payment that succeeded without provisioning.** `22-07` names this as its own worst outcome.
  The remedy today is hand-written SQL against a tenant's row.
- **An account that predates `22-05`.** Found by the author on their own account: the only
  workaround on offer was *register a new site*.

Two earlier decisions constrain what the fix may look like. `adr/0032` established that the platform
owner is authorized by a Keycloak realm role, not by any row this codebase writes — so nothing in
`Ago.Chat.Application` can check it, and `12-02`'s handler makes no second check by design.
`adr/0093` established that chat grants a **module** and never learns the word "calendar". And
`22-07`'s own reasoning, following rule 8, requires that the granted state live in the module's
database and travel over the outbox rather than being read across products on a write path.

The question this ADR answers is not *whether* an owner may grant — the item settles that — but what
must be **recorded** about a grant, and how far the word "expires" is allowed to reach.

## Decision

**One mechanism, a second caller.** `EnableModuleForSiteAsOwner` and `RevokeModuleForSiteAsOwner` are
separate commands and handlers that carry no `OperatorId` and call no `IPermissionChecker`, reaching
the identical `EnabledModule` aggregate and the identical `22-11` module-first registration path.
`RequirePlatformOwner` on `PUT`/`DELETE /api/v1/owner/sites/{siteId}/modules` is the entire
access-control story, exactly as it is for `12-02`'s read and `14-12`'s unlink.

**The grant is recorded on the entitlement it creates, not beside it.** `GrantedByOwner` and
`ExpiresAt` are columns on the `EnabledModule` row itself. A purchase and a grant are then
distinguishable wherever either is recorded, because they are the same record with different values —
a separate audit table could disagree with the row it describes, and would be believed.

**An owner may grant without an end date, but must say so.** `ExpiresAt` is a nullable member marked
`required`: a request body omitting the key is refused before the handler runs, while an explicit
`null` deserializes. "A grant with no expiry is a discount nobody remembers giving" becomes a
mechanical refusal rather than a convention.

**Expiry binds the granting side only, and this ADR says so rather than implying otherwise.** The
read every real caller goes through filters expired rows, so chat stops offering the module the
instant a grant lapses. **The module is never told.** A lapsed grant does not reach the calendar, and
the calendar does not independently refuse a call whose assertion it can still verify. Closing that
needs either the expiry to travel to the module side or a sweep at expiry; neither is built.

**Nothing but the realm role stops this becoming the normal path.** That is the answer to the item's
"it must not become the normal path", not an omission: the role is granted by no write in this
codebase, so a tenant seeking to avoid payment has no reachable route to the endpoint.

## Consequences

- The three motions above have a surface. A first client can be given the calendar without a payment
  path existing yet, which is what unblocks `22-07` from being on the critical path to a sale.
- Revocation works against a tenant's own purchase as readily as against a grant. That is deliberate —
  the support case this opens with *is* a tenant's own broken registration — and it means the owner
  route can undo something the owner did not do.
- **A cross-tenant write now exists in two places rather than one**, and both are unified only by a
  policy name. `authorization.md` and `tenant-isolation.md` both claimed no owner write surface
  existed anywhere; both had been false since `14-12` and are corrected in the same change as this
  ADR. That the claim survived one counter-example is the argument for stating the rule in one place.
- **An expired grant is a half-truth in the system.** Chat believes the module is gone; the calendar
  believes nothing changed. Until that is closed, an owner revoking a grant explicitly is the only
  action that reaches both sides.
- The route requires the deployment-wide provisioning secret in its body, so an owner cannot grant
  without also holding the anchor `adr/0095` describes. That is a narrowing, not a widening — but it
  means "platform owner" alone is insufficient authority in practice, which the role's name suggests
  otherwise.
- One more caller of the `22-11` mechanism to keep working. A change to module registration now has
  two entry points to satisfy, and only integration tests distinguish them.

## Alternatives considered

**A separate `module_grants` audit table.** The shape most systems would reach for, and it loses on a
specific failure: two records of one fact drift, and the derived one is the one people read. Putting
the distinction on the row makes disagreement impossible rather than unlikely.

**Reuse `EnableModuleForSite` with an owner flag on the command.** Fewer types, and it would have put
an `if (isOwner)` inside a handler whose permission check is its only gate — precisely the shape
`adr/0032` rejected, where an authorization decision is re-made in a layer that cannot see the claim
it depends on.

**Check the platform-owner role inside the handler as well as at the policy.** Rejected for the reason
`12-02` gives and this ADR inherits: `Ago.Chat.Application` has no port that sees claims, so the
second check would be a weaker copy free to drift from the first.

**Enforce expiry on the module side too, now.** The honest version of what "expires" ought to mean,
and deferred rather than pretended: it needs an expiry to travel over the module contract, which is a
change to `adr/0094`/`adr/0095`'s wire, and the item that removes the module channel from the internet
(`22-18`) changes the same surface. Doing both at once would have argued two things in one review.

**No expiry at all — grants are permanent until revoked.** Simpler, and it is the failure mode the
item named in advance. A trial nobody remembers giving is indistinguishable from a customer.
