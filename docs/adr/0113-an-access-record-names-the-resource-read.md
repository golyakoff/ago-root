# ADR-0113: An access record names the resource read — the mirror image of an erasure receipt naming none

- **Status**: Accepted
- **Date**: 2026-09-05
- **Stage**: 24 (`24-12`)

## Context

`24-06` found that every isolation control in this project is preventive, not evidential: nothing
records that an operator opened a conversation, viewed a phone number, or that the platform owner
looked at a tenant's data. `17-01`'s own history is the proof this matters — a real cross-tenant hole
existed for months behind controls that looked complete, and when it was found there was no way to ask
whether it had ever been used.

`adr/0112`, three days earlier in the same stage, decided that `erasure_records` must name the tenant
and the operator but never the erased person, because naming them would keep exactly the pointer the
erasure was supposed to remove. This item's own record — one row per boundary-crossing read — looks
like the same shape from a distance (a receipt, minted once, naming a site and an actor) and the
temptation is to copy `adr/0112`'s omission wholesale. That would be wrong, and the reason it would be
wrong is this ADR's whole content.

## Decision

`access_records` names **which resource was reached** — `resource_kind` plus a bare `resource_id`
(a conversation id, a channel-identity id, an enabled-module id) — whenever the access named one.
This is the opposite of `adr/0112`'s choice, made deliberately rather than by not noticing the
precedent: an erasure receipt exists to prove *the data is gone*, and naming the person keeps a live
pointer to someone who asked to disappear. An access record exists to prove *who read what*, and
withholding the resource would make the record answer a question nobody asked ("something happened,
somewhere") instead of the one the item exists to answer ("did anyone read *this* visitor's history").
Accountability is the content here, not the risk.

Consequences of that choice, each one deliberate:

- **No foreign key on `site_id` or `resource_id`, for a third reason after `adr/0111`/`adr/0112`.**
  There, evidence had to outlive its own subject's erasure. Here, a record of an access to a tenant's
  data must survive that tenant's own eventual erasure (`SiteErasureJob`'s `DELETE FROM sites`), or the
  one tenant most likely to ask "did AGO look at my data before you finished erasing me" would have the
  answer destroyed by the very process the question is about.
- **The row never carries what was returned.** `resource_id` says *which* conversation was opened, not
  what it contained — the same "metadata, not content" line every row in `personal-data.md` already
  draws for `sites.name`/`conversation_assignments`, applied to this table. Proven positively, over a
  real persisted row, by `AccessRecordRepositoryTests`.
- **Which reads are recorded is the defensible set the backlog item names, not "every gated
  endpoint": `18-07`'s cross-conversation history, the platform owner's cross-tenant reads and writes,
  and — separately, not built by this item — `20-12`'s `customer:read` in AGO Calendar.** Export and
  erasure being *requested* are already durable records (`export_requests`, `erasure_records`) and need
  no third table.
- **A read that fails authorisation is not recorded.** Nothing was read, so there is nothing to attest
  to; recording refusals is a security-monitoring concern this item's own Out-of-scope explicitly defers
  ("alerting or anomaly detection... a record first; watching it is later").
- **Two layers write this table, by design, not by drift.** `GetVisitorHistoryHandler`
  (`Ago.Chat.Application`) writes its own row because the acting operator's id is already a field on its
  own command — the same layer that made the authorization decision this row is evidence of. The
  platform-owner endpoints (`Ago.Chat.Api`) write theirs from the endpoint delegate itself, because the
  platform owner carries no domain identifier `Ago.Chat.Application` could name them by (`adr/0032`) —
  only a Keycloak `sub` claim, which `ListSitesForOwnerHandler`'s own remarks already call a transport
  concern for the *authorization* question. This ADR extends that same layering to the *audit*
  question: recording who acted is not a second, weaker copy of a permission check (nothing here gates
  anything), so reading the claim where it naturally lives does not reopen `adr/0032`'s argument.
- **Retention is 365 days, enforced by `AccessRecordPruneJob` — unlike `acceptance_records`/
  `erasure_records`, which are indefinite.** An access record is itself personal data about the
  operator or platform owner who made the access, and those two tables' indefinite retention is
  justified by what they are evidence *of* (a lawful basis; a completed erasure) — a justification that
  does not transfer to a log of ordinary, lawful reads. The number is a deliberate, unmeasured choice in
  the same family as `adr/0050`'s 30-day backup window: long enough that "was this site's data read in
  the past year" still has an answer, short enough that this table does not become the indefinite
  personal-data store this item's own Scope warns against.
- **A tenant sees AGO's own accesses to their site.** `24-12`'s own open question, answered here:
  `GetAccessRecordsForSiteHandler`'s read is filtered only by `site_id`, with no filter on `actor_kind`,
  so a row this stage wrote for the platform owner's own `OwnerSiteDetail` read comes back to that
  tenant's own Admin exactly like an operator's own row would. Withholding it would make the one
  question a tenant most wants this table to answer the one it could not.

## Alternatives considered

**Follow `adr/0112` exactly: no `resource_id`, ever.** Rejected for the reason stated above — it would
produce a record that proves an access happened without proving *which* person's data it reached,
which is the whole content of `24-12`'s own Goal ("this system can say who read *a given person's*
data").

**A single `IPermissionChecker`-style port checking the write, mirroring `adr/0016`'s RBAC.** Rejected:
the write is an audit fact, not an authorization decision, and giving it a second gate would either
duplicate the real gate (`RequirePlatformOwner`, the per-conversation comparison) or silently become a
second, weaker copy of it that could drift from the first the moment either changes — the identical
argument `ListSitesForOwnerHandler`'s own remarks already make against a second permission check on
that read.

**Record every read of every message.** Rejected before this item began (the backlog item's own
Out-of-scope): a second copy of the busiest table's own traffic, and a personal-data store in its own
right with nothing this item's Goal actually needs from it.

## Consequences

**Positive.** A tenant asked "did anyone read this visitor's data, and was one of them AGO itself" now
has an answer with a name, a kind, a resource, and a time — not merely the absence of an incident
report. `processing-instruction-facts.md`'s Element 6 moves this line out of "could not be produced".

**Negative, and stated rather than discovered.** `customer:read` in AGO Calendar — the fourth
boundary-crossing surface the backlog item names — is not built by this item: it lives in a different
repository, on a different database, and this table cannot reach across that boundary. AGO Calendar
needs its own access-record mechanism, or a documented decision that it does not, before this ADR's
claim ("who read a person's data") can be made about that product too.

**And this is the decision to reopen first if a future item finds a boundary-crossing read this ADR's
own defensible set does not cover** — the set is named, not derived from a rule, and a fifth surface
that plainly belongs is an argument for widening the enum, not for building a parallel mechanism.
