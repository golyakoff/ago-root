# ADR-0095: A module registration is provisioned over a generic contract, bootstrapped by a deployment-wide provisioning secret

- **Status**: Accepted
- **Date**: 2026-09-04
- **Stage**: 22
- **Extends**: `adr/0065` (the module contract this adds a second, provisioning-shaped route family to)
  and `adr/0094` (the per-call credential this mechanism installs on both sides). Amends neither.
- **Amended**: 2026-09-04 by `22-17` (see Consequences) — the provisioning secret can now create
  tenants, so this ADR's enumerated blast radius is wider than it was written. The decision stands;
  the limit does not.

## Context

`22-04` gave each site its own module credential, held in a row — `EnabledModule.Credential` in
`ago-chat`, `ChatModuleRegistration.Credential` in `ago-calendar`, `ModuleSiteRegistration.Credential`
in `ago-faq`. **Nothing outside a test ever wrote one.** `EnableModuleForSite` took a credential as raw
operator input and stored it on the chat side; the matching row on the module side had no writer at
all — not a console screen, not an endpoint, not a migration default. Deployed as it stood, every
chat-originated call to a module product was refused, correctly, because there was no registration to
verify against.

Both repositories were also add-and-read only: no update, no delete. So a leaked credential had no
rotation path, and a site's access had no way to end.

`adr/0094` had already named this and declined to close it: *"the registry row gains a `Credential`
beside its `EntryPoint`, supplied by whoever enables the module… no new provisioning handshake is
invented."* That was right for that item — the handshake was the larger half of another one. This is
that item.

Two constraints carry over unchanged. **Chat must not learn a product's name** (`adr/0065` decision 2,
`adr/0027`'s domain-separation half). And **there is no distributed transaction** across two
independent databases in two separate repositories: whatever makes both sides agree has to tolerate
one half succeeding while the other fails, and say so rather than leave the rows silently disagreeing.

## Decision

**Each module product exposes a second, generic route family — `/api/v1/module-registrations/{siteId}`
— authenticated by a deployment-wide shared secret distinct from the per-call credential. Chat calls it
synchronously, in the same request as the operator-facing command, and orders every write module-side
first.**

### 1. A second contract, not a fourth copy of the first

`PUT` creates, `POST …/rotate` rotates, `DELETE` revokes, `GET` reports status. The same shape as
`adr/0065`'s `/api/v1/module-tasks` family — opaque to chat, which builds every URL from
`EnabledModule.EntryPoint` and never branches on what answers it. Chat has carried a per-site,
per-module `EntryPoint` since `20-07`/`22-02`; this adds no new fact chat learns about a module, only
new verbs against a coordinate it already held.

### 2. A different secret and a different mechanism from `adr/0094`'s per-call credential

`X-Ago-Module-Provisioning-Secret` carries the raw secret, compared in constant time against a value
each module deployment holds in its own configuration (`ModuleProvisioning:Secret`). **Not**
`adr/0094`'s signed-assertion format, deliberately: that format's complexity buys something this
channel does not need. It exists to prove *"the caller is one of many already-registered sites,
cross-checked against the request body"* — a real threat on a channel a visitor's browser can reach
indirectly through the widget. This channel is admin-to-admin, low-volume, with one legitimate caller.

An absent or empty configured secret **never authenticates anything**, including an empty header:
turning this on cannot happen by omission.

### 3. Module-first, then the chat-side row — not the outbox

The handlers call the module synchronously, before writing their own row. An outbox-dispatched,
eventually-consistent alternative was rejected on rotation's own terms: "no downtime" needs the module
to confirm a credential change **before** chat starts minting calls with it. If chat switched first,
every call signed in the gap would carry a credential the module does not yet recognise — worse than
doing nothing.

### 4. Drift is detectable, and — for the likelier direction — not smoothly repairable

Module-first ordering narrows disagreement to one case: the module accepts the write and chat's own
local write then fails. A narrow window around one local database write, not a network hop. It is not
eliminated — no distributed transaction exists to eliminate it with — but it is **detectable**:
`VerifyModuleRegistration` reads chat's row and the module's `GET`, and reports whether they agree. It
is operator-invoked, gated by `site:configure`, and nothing calls it automatically.

**Repair is not the symmetric "re-run the idempotent command" it would be convenient to claim.**
Register is create-only and refuses a second `PUT`; rotate and revoke both require chat's own row to
exist before they reach the gateway. So for module-has-it-chat-does-not, none of chat's three write
commands fixes it: enable hits the module's 409, rotate never reaches the module at all. Today's remedy
is out-of-band — someone with the provisioning secret clears the orphaned module-side row through the
module's own `DELETE`, outside chat's UI. That is a real, open limitation. Upsert semantics on the
module's `PUT`, or a fallback-to-register inside rotate, would close it; neither is built.

The reverse drift fails safely: rotate and revoke both refuse without touching chat's row, so an
ongoing call correctly keeps failing rather than succeeding on stale trust.

### 5. Rotation keeps two credentials valid for a bounded, per-tenant overlap

The outgoing credential is demoted to `PreviousCredential` with its own expiry, **ten minutes** out —
an implementer's-call bound, **not a measured one**, sized to outlast the gap between the module
confirming a rotation and any request already in flight. No load test measured it; a defensible number
needs a real measurement of in-flight-call duration, which was not taken.

The window closes by wall-clock time alone. A call presenting the outgoing credential afterwards is
refused like any other invalid one. The overlap exists for a request signed *before* the switch, not
as a window a caller may rely on.

It is **per tenant** — proven against real Postgres with two tenants in both module products. Rotating
the same site twice inside one window does not stack: the second rotation discards the older previous
credential immediately, so a caller still holding the original is cut off at once rather than keeping
its own remaining grace. A sharp edge for an operator who rotates twice in quick succession, named
here rather than left to be found.

### 6. Revocation is immediate and total

Module-first deletion, no soft flag, no overlap. A grace window exists in rotation to protect a call
signed with the *legitimate* secret a moment before it changed; revocation exists precisely for the
moment a secret must stop working as fast as possible, and a window here would undercut the one thing
the operation is for.

## Consequences

- **A leaked per-site credential now has a remedy, and an ended site now has an ending** — the
  load-bearing gap `22-04`'s own author named is closed on both sides of the two-sided write.

- **The provisioning secret's blast radius is worse than the deployment-wide limit `adr/0094`
  recorded, not equivalent to it.** A holder can register, rotate or delete the registration for *any*
  site the deployment serves — not forge one call at a time, but rewrite who the legitimate
  credential-holder is, persistently. Register, rotate and delete are strictly more powerful primitives
  than sign-a-call.

  This is accepted because **a bootstrap trust anchor cannot be scoped to the per-site fact it exists
  to create.** A per-call credential can be per-site because the row it authenticates against already
  exists; the first `PUT` for a site *is* the act of bringing that row into existence, so there is
  nothing site-specific to check against yet. mTLS does not escape this either — whoever holds a
  deployment's client certificate can act on any site it serves; it changes the credential's shape and
  its revocation story, not the blast radius. The only way to avoid a deployment-wide bootstrap secret
  is not to automate provisioning at all, which is the state this item exists to leave.

- **Amended 2026-09-04 by `22-17`: the blast radius above grew, and the enumeration that made it
  checkable no longer holds.** As written, this bullet's list — register, rotate, delete a
  registration — was exhaustive because **no route reachable in production could create a tenant at
  all**; a secret-holder could only act on sites the deployment already served. `22-17` needed a grant
  to complete for a tenant the calendar had never seen, and `RegisterChatModuleHandler` now
  auto-provisions that tenant. A holder can therefore **bring accounts into existence**, without limit
  and without anyone asking.

  Accepted on the same argument as the original, and no further: the anchor cannot be scoped to a row
  whose creation is the act being authorized. It is recorded rather than absorbed, in three ways —
  `Tenant.AutoProvisionForChatModule` is a separate factory, `Tenant.AutoProvisioned` marks every row
  it wrote, and the call is logged. **There is no bound on how many such tenants can be created**, and
  none of the three protections is one. `22-18`, which removes the module channel from the internet
  entirely, remains the item that ends the exposure rather than annotating it.

- **What does not protect these routes today**, named rather than implied: no IP allowlisting, no
  audit log of provisioning calls, no rate limiting, no alerting on repeated refusals. `22-18`
  (`ago-root#402`) is the item that changes the exposure rather than mitigating it — chat and the
  module products share a cluster, so this channel need not be published to the internet at all, and
  `enabled_modules` holding zero rows means no `EntryPoint` has been chosen in production yet and the
  decision is still free.

- **`secrets.md` records `ModuleProvisioning:Secret` — one independent value per module deployment —
  as Restart.** Rotating it means editing one deployment's own configuration and redeploying it;
  nothing holds it across calls, chat never persists it, and no live traffic path carries it, so
  nothing in use stops working. (`22-11`'s own report proposed **Coordinated** and then **Breaking**;
  neither fits the table in `secrets.md`. Coordinated is for a value two places must change in order,
  and this has one canonical home. Breaking is for a value whose change a *user* feels immediately,
  and no user is on this path — the only party who can present a stale value is the operator who
  changed it.)

- **Nothing here is on the live deployment.** `enabled_modules` holds zero rows there, and with no
  secret configured every provisioning call is refused. Shipping it needs the secret generated, placed
  in the node's environment and referenced by the manifests — `ago-deploy` work, and gated on `22-18`.

## Alternatives considered

- **Reuse `adr/0094`'s signed-assertion format for provisioning too.** Rejected: different threat
  models, and folding both onto one format is the "fourth hand-kept copy" `22-11`'s own item warned
  against in substance, even though it is a second wire agreement rather than a literal new file.
- **An outbox-dispatched, eventually-consistent write.** Rejected on the ordering argument in
  decision 3 — the thing rotation promises is exactly what eventual consistency cannot give here.
- **A shared NuGet package for the provisioning wire format.** Rejected for `adr/0094`'s own reason:
  two callers with no third in sight, and `Ago.Platform.*` must never learn a product's shape.
- **`Ago.Calendar.Provisioner`'s one-shot CLI shape, generalised.** Rejected: the operation is
  two-sided, repeatable and latency-sensitive, none of which a hand-run, no-DI tool is.
