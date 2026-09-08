# ADR-0155: A tenant erasure reaches a module over the provisioning channel, and a module revoke tombstones rather than deletes

- **Status**: Proposed
- **Date**: 2026-09-08
- **Stage**: 22 (`22-30`)
- **Qualifies**: `adr/0149` rule 2's own phrase "the credentialed per-site channel (`22-02`)" — see
  *Consequences* for exactly what changes and what does not. **Placeholder number** — written by a
  background worker implementing `22-30`; the author assigns the real number and the `docs/adr/README.md`
  index row.

## Context

`22-30` builds AGO Calendar's own tenant erasure and the chat-side gate that waits for it, closing the
hole `adr/0149` named but did not fully work through: "the reconciliation check (`22-32`) becomes
necessary rather than nice, because rules 1 and 2 both assume chat knows which modules hold a tenant's
data. When that assumption is wrong — a revoke that orphaned a tenancy row... nothing else in the
system can see it." Implementing rule 2 ("a lifecycle operation completes when the module proves it")
for erasure specifically surfaced two concrete questions `adr/0149` did not answer, because neither
one is about suspension:

**First, how does chat reach a module for a tenant whose per-site channel may itself be the problem?**
`22-30`'s own backlog names three cases an erasure must still work for: a tenant whose grant is active,
one whose grant has *lapsed* (expired), and one whose grant was *revoked*. `adr/0149` rule 2's own
wording points at "the credentialed per-site channel (`22-02`)" — `EnabledModuleEndpoint`'s
per-(site, module) `ModuleCredential`, the same channel `IModuleGateway` uses for module tasks. But
`RevokeModuleForSiteAsOwnerHandler` (`22-17`/`23-13`) calls the module's own revoke endpoint before
this item, which stops that exact credential from authenticating on the module's side — by design,
`22-11`'s own Done-when. A revoked tenant is therefore precisely the tenant the per-site channel cannot
reach, which is the case this item exists to still answer for.

**Second, what survives a module revoke on chat's own side?** Before this item,
`RevokeModuleForSiteAsOwnerHandler` deleted the `EnabledModule` row outright — `IEnabledModuleRepository.DeleteAsync`'s
own doc comment called this "deletion, not a soft flag," deliberately, mirroring
`IChatModuleRegistrationRepository.DeleteAsync` on the calendar side. That row is chat's only record
that a site ever had a given module at all. Deleting it on revoke means a later erasure has no way to
learn the module ever existed for that site — the exact "orphaned tenancy row" failure `adr/0149`'s own
Consequences flagged `22-32` as needed to detect, arriving instead through the mechanism meant to
*prevent* orphaning.

Two further constraints bound the answer. `Ago.Chat.*`'s own deployment already holds a **deployment-wide**
secret for exactly this kind of call — `ModuleProvisioningSecret` (`adr/0095`/`adr/0150`), used by
`IModuleRegistrationGateway` for register/rotate/revoke/status against `/api/v1/module-registrations/{tenantId}`.
And `adr/0093`'s own Consequences already named the cost this item is spending: "Erasure spans two
databases over at-least-once delivery and must be *provable*... None of this is caused by the decision
above."

## Decision

**1. Erasure asks a module over the provisioning channel, not the per-site credential channel.**
`IModuleRegistrationGateway` gains `EraseTenantDataAsync`, calling
`DELETE /api/v1/module-registrations/{tenantId}/tenant-data` with the deployment-wide
`X-Ago-Module-Provisioning-Secret` header — the identical authentication register/rotate/revoke/status
already use, and a distinct route from `RevokeAsync`'s own `DELETE /api/v1/module-registrations/{tenantId}`
(one call ends a credential's authority; the other ends a tenant's data — folding them together would
make one HTTP verb mean two irreversible things). This works identically whether the tenant's per-site
registration is active, lapsed, or was revoked yesterday, because it depends on none of those states —
only on the module's own entry point, which chat's deployment configuration
(`IModuleEntryPointProvider`, `adr/0154`) or the tenant's own `EnabledModule.EntryPoint` copy already
names regardless.

**2. `RevokeModuleForSiteAsOwnerHandler` stamps `EnabledModule.RevokedAt` instead of deleting the row.**
The module-side revoke call is unchanged and still runs first — the credential still stops
authenticating immediately, `22-11`'s own guarantee intact. What changes is which row survives on
chat's own side: revoked and lapsed grants are now both kept (never deleted), so
`IEnabledModuleReadStore.GetAllForSiteAsync`'s existing unfiltered read — built for `23-14`'s support
diagnostics — becomes, for free, the durable list `SiteErasureJob` needs of every module a site has
ever had. The hot routing path (`GetForSiteAsync`) and the write-side lookup
(`IEnabledModuleRepository.GetAsync`) both gain a `revoked_at is null` filter, so a revoked module reads
as "not enabled" everywhere it did before this item — the tombstone is invisible to every caller except
the one that now needs its history.

**3. The calendar's own erasure is one transactional delete plus two explicit deletes a foreign key
does not reach.** `Tenant`'s own row deletion cascades through nine of `Stage20CreateCalendarSchema`'s
own foreign keys (`customers`, `events`, `workers`, `services`, `calendars`, `chat_module_registrations`,
`pending_phone_verifications` and the rest). Two tables do not cascade at all —
`role_assignment_projections` and `contact_visibility_projections`, both replicated from AGO Chat's own
outbox (`22-05`/`23-12`, `adr/0093`) and both deliberately built with no foreign key to `tenants`, the
same reasoning every outbox-fed projection in this codebase shares (a snapshot a consumer can replay is
not an owned child of the aggregate it happens to be keyed by). `TenantErasureRepository` deletes both
explicitly, in the same transaction as the tenant row. Found by proving `22-30`'s own first Done-when
against a real Postgres, not read off the schema — the fails-before demonstration is in this item's own
report.

## Consequences

- **`adr/0149`'s own "credentialed per-site channel (`22-02`)" phrase, read literally, is not what
  erasure uses.** This is a considered divergence, not an oversight: rule 2's actual content — "a
  lifecycle operation completes when the module proves it" — is honoured exactly; only the specific
  channel named in that rule's own prose is not, because that channel cannot reach the class of tenant
  this item is scoped to reach (revoked, lapsed, or never-fully-registered). Export (`22-31`) is not
  touched by this decision — its own Scope already independently says "over the credentialed per-site
  channel," and nothing here argues that case should change; a tenant asking for an export is
  overwhelmingly a tenant whose registration is live.
- **`IEnabledModuleRepository.DeleteAsync`'s own "deletion, not a soft flag" reasoning no longer applies
  to the one caller that used it.** The method itself is unchanged and still exists (nothing else calls
  it after this item), but the design principle it was written to state is now qualified: a module
  revoke *is* a soft flag, deliberately, because the alternative destroys the one fact a later erasure
  needs.
- **A revoked-then-re-enabled module leaves two rows on chat's own side** — the tombstoned original and
  a fresh grant — rather than one. `IEnabledModuleRepository.GetAsync`'s new filter keeps every ordinary
  caller pointed at the live row; `SiteErasureJob`'s own gate iterates every row regardless, so a
  tenant's erasure asks the module once per historical grant rather than once per site. Harmless
  (`EraseTenantDataAsync` is idempotent by construction — a second call for an already-erased tenant is
  "confirmed clean," not an error) but worth naming: this item did not add a uniqueness constraint on
  `(SiteId, ModuleKey)`, and one did not exist before it either — a pre-existing gap, unchanged in scope
  by this decision, flagged in this item's own report rather than fixed here.
- **The calendar's tenant-data-erase endpoint needs no `chat_module_registrations` row to answer.**
  Deliberately: gating it on that row's existence would refuse exactly the revoked-registration case
  this whole decision exists to still reach.

## Alternatives considered

- **Erasure over the per-site `ModuleCallCredential` channel, as `adr/0149` rule 2's own prose names.**
  Rejected for the reason above: it cannot reach a revoked or never-registered tenant, which is most of
  what this item is for. A variant — re-register a fresh credential via the provisioning secret
  immediately before erasing, then use the per-site channel — was considered and rejected as strictly
  more moving parts for the identical authentication guarantee the provisioning channel already gives
  directly.
- **Keep deleting `EnabledModule` on revoke; have `SiteErasureJob` ask `IModuleEntryPointProvider`
  (deployment config) for every known module key instead of reading the site's own history.** Rejected:
  it would ask *every* module this deployment has ever configured, for *every* site being erased,
  regardless of whether that site ever had it — wasted calls at best, and it discards the one piece of
  information (which modules did this site actually enable) that is a site's own history to keep, not
  a deployment-wide fact to reconstruct by asking blindly.
- **A dedicated `RevokedEnabledModule` archive table**, moving a revoked row out of `enabled_modules`
  entirely rather than tombstoning it in place. Rejected: it would need its own schema, its own
  read path for `SiteErasureJob` to query two tables instead of one, and buys nothing a single nullable
  column does not already give — the same "avoid a second table for one more field" judgement this
  codebase's own `EnabledModuleDetailSummary` remarks already make for a narrower case.
