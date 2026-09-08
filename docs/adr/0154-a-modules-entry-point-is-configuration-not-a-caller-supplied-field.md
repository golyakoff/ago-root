# ADR-0154: a module's entry point is configuration, not a caller-supplied field

- **Status**: Accepted
- **Date**: 2026-09-07
- **Stage**: 23 (`23-92`)
- **Amends**: `adr/0150` — the same reasoning, extended from the provisioning secret to the
  neighbouring `EntryPoint` field on the identical request.

## Context

`adr/0150` moved `adr/0095`'s deployment-wide provisioning secret out of the platform owner's grant
request and into `Ago.Chat.Api`'s own configuration, because the platform owner can read that secret
from the cluster anyway — asking them to paste it protected nothing and cost a second inconvenience.

The field beside it, `EntryPoint`, was left alone at the time. Trying to actually use the screen
`adr/0150` built showed why that was incomplete: the author filled it with `https://golyakov.net` —
their own site, not the module's address — and got *"module 'calendar' is unreachable: module answered
404 Not Found"*. The error was correct, and finding the right value took probing the live cluster:

| candidate | result | why |
|---|---|---|
| `https://calendar-api.reserve-me.ru` | `404`/`405` | the gateway's own HTTPRoute is an allowlist; the provisioning surface is deliberately not on the public internet |
| `https://ago-calendar-api:443` | would fail TLS | `Ago.Chat.Api` carries no internal-CA trust material for the module's own leaf certificate |
| `http://ago-calendar-api` | `401` | reachable and routed, refusing only for the missing provisioning secret |

**The author's own question was the finding**: *"you knew the address anyway — why ask me to type
it?"* `EntryPoint` is free text because `EnabledModule`'s own data model makes it a per-(site, module)
coordinate — the shape a design would want if one tenant's calendar could live on a different
deployment from another's. `adr/0093` already settled that AGO has no such case: one deployment, two
schemas, two databases. The generality is real in the model and unused in the product, and its whole
cost lands on a human retyping an infrastructure address once per grant.

**The constraint that does not move**: `ModuleKey`'s own remarks and `adr/0065` decision 2 require that
`Ago.Chat.*` never learn what a module *is* — no `"calendar"` literal, checked by
`Ago.Chat.Architecture.Tests`. Any fix has to resolve a real address without the assembly ever naming
which module it is resolving one for.

## Decision

**`EnableModuleForSiteAsOwner` no longer carries an `EntryPoint` field.** The handler resolves it from
a new port, `IModuleEntryPointProvider.TryGet(ModuleKey)`, implemented by reading the
`ModuleEntryPoints` configuration section generically by whatever key the caller supplies —
`ModuleEntryPoints:calendar`, bound the identical way `ModuleProvisioning:Secret` already is, wired by
`ago-deploy`'s own manifest rather than a `.cs` literal.

**A module the deployment has not declared is refused, by name.** `TryGet` returning `null` — an
absent key, or one that does not parse as an absolute http(s) URI — is
`Module.EntryPointNotConfigured`, a `503` naming the missing configuration key, never a blank that
would only fail later, as today's `404`, once the module is actually called.

**Configuration wins, unconditionally, because there is no longer an alternative to weigh it against.**
Every grant call resolves the entry point fresh from configuration at the moment of the call; the
persisted `EnabledModule.EntryPoint` row is what routing and every later read use, exactly as before
this item. A row written before this change keeps whatever address it already holds — this decision
governs only the moment a grant is made, never rewrites a row already on disk.

## Why this line and not another

**Configuration, not a bound options class with one property per module.** The set of module keys is
not fixed at compile time and must never be — an options class named after `"calendar"` would be the
exact literal the architecture guard exists to catch, arriving through a property name instead of a
string. Reading `IConfiguration`'s own section indexer at the moment a real caller names a real key
keeps `Ago.Chat.Infrastructure.Modules` ignorant of which keys exist while still resolving whichever one
is asked for — the identical shape `IModuleProvisioningSecretProvider` already established for one
value, generalised here to a lookup.

**A literal module key is fine in `ago-deploy`'s own manifest.** That repository is not `Ago.Chat.*`
and the architecture guard never scans it; a line naming `calendar` there is exactly what "the
deployment declares the mapping" means, and adding a second module needs only a second line, never a
code change.

## Consequences

**Positive.** Granting a declared module needs no address typed — the platform owner chooses the
module; where it lives is the deployment's own fact, read the same way its provisioning secret already
is. A wrong-but-plausible entry point (a tenant's own website, a stale address) can no longer reach the
module-registration call at all.

**Negative, and named.**

- **A module the deployment has not yet declared an address for cannot be granted at all**, not even for
  testing against an ad-hoc address. `adr/0150`'s own `VerifyModuleRegistrationAsOwner` keeps a
  caller-supplied entry point deliberately, for exactly this reason — checking a candidate address
  independently of what either side currently believes — and this decision does not touch it.
- **Adding a second module costs a manifest line, not a config toggle a non-engineer could make.**
  `ModuleEntryPoints:<key>` lives in `ago-deploy`'s own `k8s/base/api.yaml`, so wiring a new module's
  address is a pull request against infrastructure, the same weight `MODULE_PROVISIONING_SECRET` already
  carries.
- **The wire contract changed.** `GrantModuleRequest`/`GrantModuleResponse` no longer carry `EntryPoint`;
  any caller still sending the old field has it silently ignored by minimal-API model binding, exactly
  as `provisioningSecret` already is after `adr/0150`.

## Alternatives considered

**Keep `EntryPoint` as caller input, only fix the console's hint text.** Rejected — and rejected by the
author directly: documenting the correct value while still asking a human to retype it is entrenching
the thing that made granting hard, not fixing it.

**A fixed options class with one property per known module (`CalendarEntryPoint`, `FaqEntryPoint`, …).**
Rejected: the property name itself would be the literal the architecture guard exists to catch, and
every new module would need a code change in an assembly that must stay ignorant of what a module is.

**Keep the field, but default it server-side only when blank.** Rejected as a silent precedence rule
nobody could diagnose — the item's own brief calls this out directly: a caller-supplied value quietly
overridden (or a blank quietly filled) is exactly the "support call nobody can diagnose" this decision
exists to avoid. Removing the field entirely is the version of "config wins" that cannot be circumvented
by accident.
