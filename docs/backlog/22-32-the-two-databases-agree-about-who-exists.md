# the two databases agree about who exists, and something says so out loud

- **Stage**: 22
- **Status**: ready
- **Depends on**: nothing. **This is the one of the four to build first**, despite the number.
- **Decision**: none needed — see *Why this needs no ADR*.
- **Split out of `22-08`** on 2026-09-07 (rule 15). It was the "and the fourth thing, which is smaller
  but sharper" in that item's own text.

## Goal

Somebody can find out, without asking anyone, whether every account with the calendar add-on has
exactly one calendar tenant and whether any calendar tenant exists without an account. Today nobody
can, and nothing would notice if the answer were no.

## Why this one goes first

It is two reads and a report. It needs nothing from `22-08`, `22-30` or `22-31`, and it is the only
one of the four that can answer the question those three all assume: **has drift already happened on
the live node?** Half-failed provisioning and half-failed deletion both show up here first, and
neither shows up anywhere else — a stranded calendar tenant is invisible to every screen in the
product, because every screen is scoped by an account that no longer points at it.

It is also the cheapest possible way to find out whether the hole `22-30` describes has already been
walked into.

## What is actually true today, verified 2026-09-07

Three ways the invariant can already break, and none of them is theoretical:

- **Half-failed provisioning.** `22-07`'s own text names it — "payment succeeded, provisioning did
  not. Money taken and no calendar is the worst outcome here. Idempotent retry the outbox gives; what
  it does not give is anyone noticing — see `22-08`." This is that item, and this is the noticing.
- **A revoke.** Chat's `RevokeModuleForSiteHandler` deletes the `EnabledModule` row; the calendar's
  `RevokeChatModuleRegistrationHandler` deletes only its registration row. The `tenants`, `customers`,
  `events` and `workers` rows stay, with nothing on either side recording that they do. `22-30` covers
  this at length; here it matters only as a source of drift the check must be able to see.
- **A quota grant that can never arrive.** `GrantModuleQuantityHandler` exists, is registered in DI
  and is covered by tests — and **no route anywhere calls it.** `Ago.Chat.Api/Modules/ModuleEndpoints.cs`
  maps get/put/rotate/revoke/verify; `Owner/OwnerModuleEndpoints.cs` maps grant and revoke; neither
  carries a quantity, and `EnableModuleForSite` has no quantity field. So `Tenant.WorkerQuota` on the
  calendar side is `0` for every tenant that will ever exist, and no calendar tenant can create a
  first worker. That is a defect of `22-07`'s rather than of this item's, filed separately — but it is
  exactly the class of thing a reconciliation report surfaces on its first run and nothing else does.

## Scope

- A check that reads both databases and reports the two asymmetries:
  - an account with a module registration and no tenant row on the module side;
  - a tenant row on the module side with no account that names it.
- It reports **counts and identifiers, not rows**. This is a cross-tenant read; keeping it to ids and
  counts is what stops it from being a third copy of anybody's personal data, and is why it does not
  need an `access_records` entry under `adr/0113` (it reaches no person's data to record a reach of).
  If it ever grows a column that names a human, that judgement changes and the item that adds the
  column owns it.
- It runs somewhere it will be seen. Cheapest honest shape: a script run from the node with both
  connection strings, on a schedule, whose non-zero output reaches the same place `15-03`'s alerts do.
  A second, worse shape is a service — rejected below.
- What the check finds on its first run against the live deployment goes in the report, whatever it
  is. That number is the actual deliverable; the script is how it was obtained.

## Out of scope

- **Repairing anything it finds.** A reconciliation that fixes drift automatically is a program that
  deletes a tenant's data on the strength of a join, and the first time it is wrong it is
  catastrophically wrong. This one reports; a person decides. `module-grant-and-revoke.md` is where a
  repair procedure would live.
- Suspension (`22-08`), erasure (`22-30`), export (`22-31`).
- Reconciling anything other than tenancy — quotas, permissions and the contact-visibility rung are
  each snapshot-projected and self-correcting on redelivery, and none of them can strand a row.

## Done when

- [ ] The check exists, reads both databases, and reports both asymmetries.
- [ ] It has been run against the live deployment and its output is in the report — including, and
      especially, if the output is "none".
- [ ] Its non-zero result reaches a person by the route `15-03` already established, rather than by
      somebody remembering to look.
- [ ] It reports identifiers and counts only, and that is asserted rather than assumed.

## Why this needs no ADR

Nothing here is a choice between defensible alternatives. The invariant is stated in `adr/0093`'s own
consequences, the check is a read, and the one judgement — report rather than repair — is a straight
application of a rule this project already follows everywhere else (`22-07` deactivates rather than
deletes; `24-09` rewrites rather than deletes whole; `adr/0118` refuses rather than guesses). An ADR
would be a document saying that a report is safer than an automatic deletion, which is not an argument
anybody is going to have.

## Open questions

- **A script with both connection strings is a new place two credentials meet.** `secrets.md` should
  say so, and the item should decide whether it runs as a `CronJob` in the cluster with two secret
  mounts or as a thing a person runs from the node during an investigation. The second is smaller and
  answers "is it drifting right now?" worse. Not the author's question unless the answer is the first,
  which adds a scheduled workload holding credentials to two databases.
