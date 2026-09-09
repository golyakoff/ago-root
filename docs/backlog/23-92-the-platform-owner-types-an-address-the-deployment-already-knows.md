# the platform owner is asked to type an address the deployment already knows

- **Stage**: 23
- **Status**: done — `ago-chat#224`, `ago-console#156`, `ago-deploy#168`; `adr/0154`
- **Depends on**: `adr/0150` is the decision this applies to the neighbouring field. `23-87` made
  provisioning work at all, which is what exposed this.
- **Found**: 2026-09-07, by the author trying to grant the calendar on the demo stand — and then asking
  the better question about the answer they were given.

## What happened

The author filled the platform owner's grant form, put `https://golyakov.net` in **Entry point**, and got
*Module 'calendar' is unreachable: module answered 404 Not Found*. The error was correct.

Establishing the right value took probing the cluster:

| candidate | result | why |
|---|---|---|
| `https://calendar-api.reserve-me.ru` | `404`/`405` | the `ago-calendar-api` HTTPRoute is an allowlist — `/` as **Exact**, plus `/healthz`, `/api/v1/console`, `/api/v1/calendars`, `/api/v1/embed`, `/api/v1/me`. The provisioning surface is deliberately not on the public internet, so the gateway answers before the app does |
| `https://ago-calendar-api:443` | would fail TLS | the Service serves 8443, but `ago-chat-api` mounts no volume except `/tmp` and so does not carry `22-24`'s internal CA |
| `http://ago-calendar-api` | **`401`** | reachable and routed, refusing only for the missing provisioning secret |

**The first draft of this item said to write that value down in the runbook and fix the console's hint.**
That was the wrong deliverable, and the author said so: *"you knew the address anyway — why ask me to type
it?"* Documenting the correct value is carefully entrenching the thing that made it hard.

## The actual finding

**`EntryPoint` is free text because the model makes it a per-(site, module) coordinate** — the shape you
would want if one tenant's calendar could live on a different deployment from another's. AGO has no such
case and is not planning one: `adr/0093` is one deployment, two schemas, two databases. So the generality
is real in the data model and unused in the product, and its whole cost lands on a human retyping an
infrastructure address once per site.

**This argument was already won on the field directly beside it.** `adr/0150` took the provisioning secret
out of the request body and put it in `Ago.Chat.Api`'s configuration, reasoning that the platform owner can
read it from the cluster anyway, so making them paste it is a second inconvenience rather than a second
lock. The entry point is the same kind of value — something the deployment knows about itself — and the
same reasoning applies unchanged.

## The constraint that shapes the fix, and it is not negotiable

**Chat must not learn what a module is.** `ModuleKey`'s own remarks and `adr/0065` decision 2 are explicit:
the key is an opaque string, there is no `"calendar"` literal anywhere in `Ago.Chat.*`, and
`Ago.Chat.Architecture.Tests` guards that as a checked property rather than a convention. A lookup table in
code would be the exact boundary crossing the design exists to prevent, arriving through a data model
instead of a `ProjectReference`.

**Configuration is not code, and that is the whole opening.** A section read generically by key —
whatever key the caller supplies, resolved against what the deployment declares — keeps the assembly
ignorant while the deployment supplies the mapping. That is structurally identical to how
`ModuleProvisioning:Secret` is now bound, and it introduces no literal the architecture test would catch.

## Scope

- **A module the deployment declares needs no address typed.** The owner chooses the module; where it
  lives comes from configuration, the way its provisioning secret already does.
- **The field does not silently become a hidden default.** If a deployment declares nothing for a key,
  that must be a legible refusal naming the missing configuration — not a blank that fails later as a 404,
  which is precisely today's failure with an extra step.
- **`ago-deploy` declares it**, alongside `MODULE_PROVISIONING_SECRET`, which `23-87` added in the same
  place for the same reason.

## Where this is likely to go wrong

- **Do not reintroduce the literal.** The moment `Ago.Chat.*` contains `"calendar"`, the architecture test
  should fail — and if a change makes that test pass while adding module knowledge, the test is what needs
  looking at, not the rule.
- **Existing rows.** `EnabledModule.EntryPoint` is persisted per row. Decide whether stored values keep
  winning over configuration, or configuration wins, and say which — a silent precedence rule is a support
  call nobody can diagnose.
- **The generality may be wanted later.** Removing a per-site field is easy to regret. The honest position
  is that it is unused today and its cost is paid every grant; if it is kept in the model, it should stop
  being something a person is asked for.

## Done when

- [x] Granting a declared module needs no address typed, and no literal module name enters `Ago.Chat.*`.
- [x] A module the deployment has not declared is refused with a message naming what is missing.
- [x] Whether a stored entry point or configuration wins is decided and written down.

## Outcome

The Entry point field is gone from the platform owner's grant form entirely. `IModuleEntryPointProvider`
resolves whatever key the caller supplies against what `ago-deploy` declares — no literal module name
enters `Ago.Chat.*`, checked by `Ago.Chat.Architecture.Tests`. An undeclared key is refused by name
(`Module.EntryPointNotConfigured`) rather than left blank to fail later as a 404. `ago-deploy` declares
`http://ago-calendar-api` — **deliberately and temporarily plain HTTP**, not yet the intended
`https://ago-calendar-api:443`, because `ago-chat-api` mounts no volume carrying `22-24`'s internal CA
yet. `23-93` is the item that closes that gap; this configured string becomes `https://` only after
`23-93` lands and the leg is proved, never before. Decided in `adr/0154`.
