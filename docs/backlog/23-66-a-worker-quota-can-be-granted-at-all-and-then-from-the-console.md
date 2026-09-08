# a worker quota can be granted at all, and then from the console

- **Stage**: 23
- **Status**: ready — **and what remains is one live demonstration, not code**
- **Depends on**: `23-65` shares the screen but not the promise. `adr/0150` is the decision for the
  console half.
- **Found**: 2026-09-07, while designing `22-08`, and verified independently before filing.

## The half nobody knows about

`Tenant.WorkerQuota` in `ago_calendar` is **zero until granted**, and its own remarks say
`GrantWorkerQuota` is written only by the outbox consumer projecting `ago-chat`'s grant — *never by a
request this product serves directly.*

In `ago-chat`, `GrantModuleQuantityHandler` exists and is registered in DI. **It has no HTTP route.**
Nothing in `Ago.Chat.Api` references it; `ModuleEndpoints` and `OwnerModuleEndpoints` map get, put,
rotate, revoke and verify, and no grant of a quantity.

So nothing can ever raise the number. **`WorkerQuota` is zero for every tenant that will ever exist,
and no calendar tenant can create their first worker** — after a successful module grant, on a
correctly provisioned tenant, with everything else working.

`22-07`'s first Done-when — *results in a calendar the tenant can configure, with no manual step
anywhere* — is ticked and is not true.

## Why this is one item and not two

A console screen for a quota is a screen calling an endpoint that does not exist. Building the screen
first leaves the product no better; building the route first leaves a capability only `psql` can reach.
Neither half lands green alone, which is exactly the test `CLAUDE.md` rule 15 gives for keeping them
together.

## Scope

- **The route that has never existed**: a platform owner grants a module quantity for a tenant, through
  the same owner-authorised path `23-65` establishes, so the browser holds no secret.
- **The console screen** that calls it, on the same tenant detail as the module grant.
- **Lowering a quota is not the same act as raising one.** `WorkerQuotaPolicy.SelectWorkersToDeactivate`
  already exists and decides who becomes the excess. A screen that silently deactivates somebody's
  staff is a screen that must say so before it does it.
- **The projection must be shown arriving.** Chat grants, the calendar projects, and the tenant's
  own screen reflects it. A test that stops at chat's own row proves the half that was never broken.

## Where this is likely to go wrong

- **The bound.** `Tenant.WorkerQuota`'s own remarks call the wait for the projection *a bounded wait
  rather than a manual step*, and say the item states the bound. State it.
- **Zero is a legitimate quota** — a tenant with the module and no workers yet. Do not let "not granted"
  and "granted zero" become the same thing on the screen.

## Out of scope

- Granting or revoking the module itself — `23-65`.
- What a tenant is charged. This is the entitlement, not the invoice.

## Done when

- [x] A platform owner can grant a worker quantity for a tenant, and it reaches `ago_calendar`.
      Proven by `ModuleQuantityGrantedWireTests` in `ago-calendar` — a real Testcontainers broker, the production `RabbitMqEventPublisher`, and this repository's own production consumer started as `Ago.Calendar.Worker` registers it. The one stand-in is chat's own process, which a single repository cannot run.
- [~] A tenant with the module and a granted quota can create their first worker — end to end, shown.
      **Half shown, 2026-09-08, and the remaining half is blocked.** The grant happened and the calendar auto-provisioned its tenant, which closed `23-87`. Creating a first worker was not reached, for two reasons found in that order: the tenant's own roles carry no calendar permission (`23-102`), and `worker_quota` is **0** for that tenant, so this item's own route has still never been exercised against a real grant.
- [~] Lowering a quota states what it will deactivate before it does it.
      **Carried out to `23-88`.** Nothing reads the quantity downwards — no confirmation, no count of what exceeds a new number, no statement of what happens to the workers above it.
- [~] The projection bound is stated, and the wait is bounded rather than hoped for.
      **Carried out to `23-89`.** The bound is real and unstated: the console writes the grant and returns, nothing says it is not instant, and nothing polls.
- [x] `22-07`'s first Done-when is either true or corrected to what actually shipped.
      Corrected rather than made true. `22-07`'s first box claimed a grant results in a calendar the tenant can configure with no manual step anywhere; `WorkerQuota` was zero and nothing could raise it.
