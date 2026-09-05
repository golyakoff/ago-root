# ADR-0118: Revoking a tenant's own purchase is refused unless forced, and the override is recorded in its own table

- **Status**: Accepted
- **Date**: 2026-09-05
- **Stage**: 23 (`23-13`)

## Context

`22-17` (`adr/0098`) gave the platform owner one route to revoke a module - `DELETE
/api/v1/owner/sites/{siteId}/modules/{moduleKey}` - and it worked identically whether the row being
removed was a grant the owner made or a module the tenant paid for. That was deliberate at the time
(`RevokeModuleForSiteAsOwnerHandler`'s own remarks: "the owner is not scoped by what the tenant did"),
and it is also exactly the shape `docs/design/flows.md` 5.3 later named as a **must never happen**:
*"undoing something without seeing it was not yours... that asymmetry has to be visible at the moment
of acting."* `docs/design/decisions.md` §6's *"`--force` exists, and it is recorded"* amendment settled
the shape - an explicit flag, a required reason, one record per use - without settling the mechanics
this ADR states.

Three earlier decisions in the same two days argued what a record of an exceptional act may name:
`adr/0111` (an acceptance record survives the erasure of its own subject), `adr/0112` (an erasure
receipt names the tenant and the operator, never the erased person), `adr/0113` (an access record names
the resource read, the mirror image of `adr/0112`). This item's own record is a fourth instance of the
same question, asked about a different act: not *reading*, not *erasing*, but *overriding a tenant's
own paid-for entitlement against their will*.

## Decision

**`RevokeModuleAsOwnerRequest` gains `Force` (`bool`, default `false`) and `Reason` (`string?`, default
`null`) as plain optional members - not the `required`-nullable trick `GrantModuleRequest.ExpiresAt`
uses.** That trick forces a caller to *state* a field regardless of its value, which is right when
omitting it is ambiguous (an expiry: forgot, or meant "forever"?) and wrong here: omitting `Force` is
never ambiguous - it unambiguously means "not forcing", the always-safe reading, and must never itself
demand ceremony. The asymmetry is the point: revoking a grant the owner made stays exactly as easy as
it was under `22-17`.

**`RevokeModuleForSiteAsOwnerHandler` reads `EnabledModule.GrantedByOwner`.** When it is `false` - the
tenant's own purchase - the revoke is refused with `Module.RevokePurchaseRequiresForce` unless `Force`
is set. When `Force` is set, `Reason` must be a real, non-blank, bounded string
(`Module.RevokeReasonRequired` otherwise) - "a blank reason is the same failure as a defaulted expiry"
(`23-13`'s own brief). **This check runs first, unconditionally on `Force`, before the handler loads
the row or learns whether `GrantedByOwner` made forcing necessary at all.** The alternative - checking
the reason only once the row's own `GrantedByOwner` is known - would make one identical request body
succeed or fail depending on a fact the caller cannot see up front, which is a harder shape for someone
running a support ticket to reason about than "state a reason whenever you set the flag, full stop."

**The override, when actually exercised (`Force` set *and* the row was a self-service purchase), is
recorded in its own table, `module_revoke_overrides`** - one row per exercise: who, when, which site,
which module key, and the free-text reason. Setting `Force` against a grant the owner made is accepted
(no new ceremony on that path) but writes nothing: nothing was overridden, so there is nothing to
attest to - the same "a read that fails authorisation is not recorded, because nothing was read" shape
`adr/0113` already gives `access_records`.

**No foreign key on `site_id` - the fourth instance of `adr/0111`/`adr/0112`/`adr/0113`'s own
mechanism, not a fresh judgement call.** A tenant whose purchase was overridden and who later closes
their account (or is erased) is exactly the tenant most likely to ask, later, "who took this away from
me, and why" - a cascading foreign key would let the answer disappear with the account, which is the
one outcome this record exists to prevent. `module_key` carries no foreign key either, for a related
but distinct reason: by the time this row is written, `enabled_modules`' own row for that (site,
module) pair has already been deleted (the handler's own module-first-then-delete ordering, unchanged
since `22-11`), so there is no live row left to reference.

**The recorded subject is the caller's Keycloak `sub`, read at the endpoint and passed into the command
as `RevokedBy` - recorded, never authorising.** `RequirePlatformOwner` on the route remains the entire
access-control story; `Force`/`Reason` gate a business decision the caller was already authorized to
make, the same way `EnableModuleForSiteAsOwnerHandler`'s own `ExpiresAt` bound is a business rule and
not a second permission check.

**Retention is indefinite, chosen rather than defaulted** - deliberately not `access_records`' 365-day
window. `access_records` prunes because it is evidence of ordinary, lawful reads by AGO's own staff;
this table is evidence of an exceptional act taken *against* a tenant, and `decisions.md` §6 states
plainly why it must survive: *"that is the act which later has to be justified, possibly to the person
it was used against."* A pruned row could not support that claim five years on.

## Alternatives considered

**A column on `enabled_modules` itself, the same place `GrantedByOwner`/`ExpiresAt` live
(`adr/0098`).** `adr/0098`'s own "a second table would be a second place the facts could drift"
argument governs those two columns precisely because they describe a row that keeps existing. This
record describes an act against a row that is, by the time it is written, one statement away from
being deleted - there is no still-existing row left for a column to drift from, which is the one case
`adr/0098`'s argument does not reach. Rejected for the reason it does not apply here rather than
argued down on its own merits.

**A `module_grant_audit`-named table, reusing the name of the migration that added `GrantedByOwner`/
`ExpiresAt` (`Stage22AddModuleGrantAudit`).** No such table exists - that migration's name described
adding two columns to `enabled_modules`, not creating a separate audit table, and a reader expecting
one from the name alone would be wrong. Stated here plainly so the next reader who goes looking for
`module_grant_audit` finds this paragraph instead of a second, half-built table.

**Folding this into `access_records` (`adr/0113`), adding a `reason` field to
`AccessRecordToWrite`.** Rejected: `access_records` deliberately holds nothing about *why* a
boundary-crossing surface was reached, only that it was and by whom - `adr/0113`'s own "an access
record ... answers the question 'who read what', not 'why'". Widening it to carry a justification
would make one port answer two questions, the identical reasoning `IExportRequestRepository`'s own
remarks give against widening `IErasureRequestRepository` to carry export's own status enum.

**The `required`-nullable trick on `Force`, mirroring `ExpiresAt`.** Rejected - this type's own
Decision states why: omitting `Force` is never ambiguous, so forcing a caller to state it anyway would
add ceremony to the one path (`GrantedByOwner` `true`) this item exists to leave untouched.

**Checking `Reason` only after loading the row and learning `GrantedByOwner`.** Rejected: it would make
an identical request body succeed or fail depending on a fact the caller cannot see up front - see the
Decision above for the full argument.

## Consequences

**Positive.** An entitlement a tenant paid for now visibly costs more to take away than one the owner
granted, exactly at the moment someone is about to do it - `flows.md` 5.3's own "must never happen" no
longer can, mechanically rather than by convention. A real justification survives the row it describes,
answerable to the tenant it was used against, indefinitely.

**Negative, and stated rather than discovered.** `Reason` is free text and may incidentally name a
third person - the tenant's own customer, if that is who prompted the override - the same caveat
`conversation_notes` already carries for an operator's own free-text annotation. Indefinite retention
of a table capable of holding that is a real, accepted cost, not an oversight; a reason that cannot say
what happened would not be a justification, which is the whole point of building this table at all.

**Two writes for one HTTP call, on the forced-purchase path.** `OwnerAccessRecorder` already writes an
`access_records` row for every module revoke (`adr/0113`); this item adds a second, `module_revoke_overrides`,
row for the subset that overrides a purchase. They answer different questions - "who reached this
route" versus "why was this specific override used" - and merging them would be the rejected
alternative above.

**Suspending a tenant remains undecided**, restated from `decisions.md` §6's own "noted, not decided":
if the real need is to stop a law-breaking tenant entirely, this flag is a workaround - the widget
keeps working, the keys stay valid, conversations continue. That is a different action and needs its
own item; this ADR does not narrow that question, and the next item to widen it should read `23-13`'s
own Out of scope before assuming this table is where a suspension record would go.
