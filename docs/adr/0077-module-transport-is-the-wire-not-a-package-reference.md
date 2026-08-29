# 0077: A chat module's transport is the wire, confirmed by a real measured hop, not a package reference

## Status

Accepted

## Context

`adr/0065` fixed the shape of a chat module — `Ago.Chat.*` carries a `moduleKey`, a `task` and a
`step`, never opens the payload, and owns a closed vocabulary of primitives a module fills in. It
deliberately left the transport open, with a stated leaning: over the wire, not an in-process package
reference, because most conversation steps run at human pace and an unreachable module already has an
honest degradation (the escape to an operator the contract requires regardless). `20-07`
(`docs/backlog/20-07-calendar-becomes-a-chat-module.md`) is the item that had to actually pick, because
picking without a real module in hand — the premature-generalisation failure mode this project keeps
naming — was exactly what `adr/0065` refused to do.

Two real shapes were on the table by the time `20-07` started:

1. **A package reference.** `Ago.Chat.*` calls `Ago.Calendar.*`'s application layer directly, in
   process. Compile-time checking, zero network hop, but a product-to-product code dependency —
   `adr/0012` (why AGO Chat and AGO Calendar are separate repositories at all) gives no precedent for
   one product's code depending on another's, and `Ago.Platform.*`'s own "the platform never
   references a product" rule (CLAUDE.md) would need a parallel rule invented for products referencing
   each other, which is a second exception to the same principle for no stated reason.
2. **Over the wire.** A plain HTTP contract (`Ago.Chat.Infrastructure.Modules.HttpModuleGateway` calling
   `Ago.Calendar.Api/ChatModule/ChatModuleTaskEndpoints.cs`), wrapped in the same resilience pipeline
   (timeout/retry/breaker/bulkhead, `Ago.Platform.Resilience`) every channel adapter already uses. No
   compile-time checking across the boundary — the wire contract in
   `Ago.Chat.Infrastructure.Modules.ModuleWireContract` and `Ago.Calendar.Contracts.ModuleTaskContracts`
   is hand-synchronized between the two repositories, the same way `14-02`'s/`14-07`'s own outbound
   channel clients are hand-synchronized against MAX's/Telegram's published API shapes.

## Decision

**The wire**, confirmed rather than reopened — `adr/0065`'s own leaning was correct and this item's
planning section found no new argument against it (see `docs/backlog/20-07-...`'s "Decided in
planning, 2026-08-29" section for the full reasoning trail). A package reference would create the one
kind of dependency this codebase's separation of `ago-chat` and `ago-calendar` into different
repositories, with different NuGet-packaged platform dependencies (`docs/architecture/repositories.md`)
exists to prevent — a second product would need the same carve-out, and by the third the "no
product-to-product reference" rule would have no content left. The wire keeps `Ago.Chat.*` capable of
routing to a module it has never been compiled against, which is the actual property `adr/0065`'s
closed-vocabulary contract is for.

## The measured hop

`docs/backlog/20-07-...` named this ADR's job as recording the transport decision "with the measured
step latency" — not an assumed number. Measured 2026-08-29, on this workstation, over loopback
(`localhost`), a real `POST /api/v1/module-tasks/` against a real `Ago.Calendar.Api` host (real
Postgres via `dotnet ef database update`, no Testcontainers indirection), ten sequential requests via
`curl -w "%{time_total}"`:

```
0.043175  (first request - JIT warmup + connection-pool establishment)
0.003744
0.007551
0.001558
0.001544
0.001656
0.001665
0.001959
0.001694
0.076612  (one outlier - not reproduced on a repeat run)
```

**Steady-state: 1.5-2.0 ms per hop.** The request exercised the real ASP.NET Core pipeline end to end -
model binding, the handler, a Postgres round trip checking for the tenant's configured calendar
(returning `chat_module_task.not_configured`, since no calendar was seeded in this measurement's
throwaway database - the error path, not the full booking-lookup happy path, but the same framework and
network overhead either way, which is what this number is actually about).

**This is the argument `adr/0065` made in the abstract, now with a real number behind it**: a
conversation step runs at the pace of a person reading a message and typing a reply - hundreds of
milliseconds to seconds, at minimum. A ~2 ms network hop is roughly three orders of magnitude below
that floor and does not register against it. The wire's cost is not latency; it is the resilience
pipeline's own responsibility (timeout/retry/breaker) for the case the module is unreachable, which is
required regardless of transport shape - an in-process call can throw too, and would still need the
same escape-to-an-operator handling `adr/0065` already specifies.

**Caveat, stated plainly**: this measurement is one hop, on one workstation, over loopback, against the
error path. It is not a load-tested number and does not stand in for one - `docs/architecture/nfr.md`'s
own load-test discipline (`load/`, Stage 6) is a different, heavier bar than what this ADR needed to
answer ("is the wire's overhead relevant to a human-paced conversation", not "how many concurrent
module tasks can this deployment sustain"). A real load figure, if one is ever needed for capacity
planning, belongs in `load/` under `load-test`, not retrofitted into this number.

## Consequences

- `Ago.Chat.*` and `Ago.Calendar.*` stay free of a compile-time reference to each other's Application
  or Domain layers. `Ago.Chat.Infrastructure.Modules` and `Ago.Calendar.Contracts` are the only two
  places either repository's own code names the other's wire shape, and both are hand-synchronized
  documentation-by-code, not a shared package.
- A third module (a second `Ago.Xxx.*` product) reuses the identical shape - one more
  `IModuleGateway`-shaped HTTP client, resilience-wrapped the same way, no new pattern to invent.
- **No service-to-service authentication exists yet** between `Ago.Chat.*` and `Ago.Calendar.*` on this
  wire - `ChatModuleTaskEndpoints.cs`'s own remarks name this plainly as a real, open gap, not solved by
  this decision and not blocking it either, since nothing on this wire is reachable by a browser (no
  `Origin` header is sent server-to-server, so CORS was never the relevant control here). Left as a
  named follow-up rather than an invented ad hoc scheme for this one boundary.
- The resilience pipeline (`ModuleResiliencePipelines`/`ResilientModuleGateway`) is composition-root
  wiring in `Ago.Chat.Module`, identical in placement to `ChannelResiliencePipelines` - the boundary
  decides to protect itself; the adapter (`HttpModuleGateway`) stays a plain "call it, translate the
  answer" class.
