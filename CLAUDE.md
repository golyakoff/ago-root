# AGO Platform — project guide for AI sessions

**AGO Platform** is the substrate: hosting, realtime transport, messaging, persistence, caching,
object storage, observability. It knows nothing about any particular product.

**AGO Chat** is the first product on it: an embeddable customer-support chat. A shop drops a
`<script>` tag on its site, visitors chat from a widget, operators answer from a console.
**AGO Ads** (contextual ads) is planned as the second product and must be an *additive* change —
a new repository (`ago-ads`) plus its own hosts, with no edits to the platform's shape.

Namespaces follow that split: `Ago.Platform.*` vs `Ago.Chat.*`. Products depend on the platform;
**the platform must never reference a product** — and cannot, because they are separate repositories
and the platform ships as NuGet packages (`docs/architecture/repositories.md`, `docs/adr/0012-*`).
Before putting anything in `Ago.Platform.*`, check the qualifying rules in
`docs/architecture/clean-architecture.md` — premature generalisation is the failure mode of a platform layer.

**This repository (`ago-root`) holds no code.** It holds the rules, the decisions and the plan.
Code lives in sibling repositories, reachable here as `platform/`, `chat/`, `widget/`, `console/`,
`deploy/` (`docs/runbooks/workspace.md`). AGO Chat deploys as three hosts — `Ago.Chat.Api`,
`Ago.Chat.Worker`, `Ago.Chat.Webhooks` — split by failure profile, not by domain (`docs/adr/0013-*`).

**Everything is public.** Never write a secret, a token, a real endpoint or anyone's data into any of
these repositories — including in a fixture, a manifest or a commit meant to be fixed later. Write
every note, backlog item and comment as if a reviewer will read it, because one will.

This is a **portfolio project**. Its purpose is to demonstrate, in reviewable form:
backend concurrency, database work under load, message-broker work, and Clean Architecture.
Optimise for *code a senior reviewer would call correct and well-reasoned*, not for feature count.

## Stack

- .NET 10 / C# 14, ASP.NET Core Minimal API + SignalR
- PostgreSQL — EF Core for writes, Dapper for read models (see `docs/adr/0004-*`)
- RabbitMQ now, Kafka later — behind one abstraction (`docs/adr/0006-*`)
- Redis — cache, rate limits, connection registry, presence. Never a source of truth
- S3-compatible object storage (MinIO locally) for attachments — bytes never pass through the API
- NGINX Gateway Fabric (Gateway API) at the edge, no sticky sessions (see `docs/architecture/edge.md`, `adr/0014`)
- Kubernetes (Docker Desktop) + Kustomize, OpenTelemetry → Prometheus/Grafana/Jaeger
- Frontend: embeddable widget (TypeScript, Shadow DOM); operator SPA framework is **undecided until Stage 5**

## Non-negotiable rules

1. **Dependency rule.** `Domain` references nothing. `Application` references `Domain` only.
   `Infrastructure.*` references `Application` + `Domain`. Hosts reference everything and are the
   only place where DI wiring lives. Arch tests enforce this — never "temporarily" break it.
2. **Every external resource sits behind a port** declared in `Application/Abstractions` and
   implemented in an `Infrastructure.*` project. No `DbContext`, `IConnection`, `IDatabase`,
   `HttpClient`, `DateTime.Now` or `Guid.NewGuid()` inside Domain or Application.
3. **No sync-over-async.** No `.Result`, `.Wait()`, `.GetAwaiter().GetResult()`, no `async void`
   (except event handlers that do not exist here). Every async API takes a `CancellationToken`.
4. **Writes go through the outbox.** A state change and its integration event are committed in one
   transaction; publishing is a separate step. Never publish from inside a request handler.
5. **Consumers are idempotent.** At-least-once delivery is assumed everywhere.
6. **Message order is guaranteed per conversation, never globally.** See `docs/architecture/concurrency.md`.
7. **Performance claims need numbers.** If a change is justified by throughput or latency, it needs
   a load-test run in `load/` and a number in the report — not an assertion.
8. **Never cache what a write decision depends on.** Capacity checks, sequences, and any
   compare-and-set read come from the database inside the transaction (`docs/architecture/caching.md`).
9. **Never commit.** `git commit`, `git push`, `git commit --amend`, `git rebase` and anything that
   rewrites history are the author's, always. Make the file changes, report them, stop. Ask and wait
   for an explicit yes if a commit genuinely seems needed. Creating branches or `git init` is fine.
   Draft commit messages never carry a `Co-Authored-By` trailer for an AI session — the author
   commits, so the author is the sole author of record.
10. **Work happens on a feature branch**, one branch per slice/backlog item. An MR is the branch
    *rebased onto `main`* with the full suite green **after** the rebase — never `main` merged into
    the branch (`docs/conventions/git-workflow.md`).
11. **Time is UTC `DateTimeOffset`, always.** Store `timestamptz`, transport ISO-8601 with an
    explicit offset, render in the user's IANA zone when supplied and otherwise render UTC *labelled
    as UTC*. `DateTime` and `DateTime.UtcNow` are banned outside Infrastructure; time comes from
    `IClock`. Ordering never depends on a clock — it uses the server-assigned `sequence`
    (`docs/conventions/date-and-time.md`, `docs/adr/0011-*`).

## Teaching mode (important)

The author is deliberately learning Clean Architecture. Whenever you place a file, introduce an
interface, or choose a layer, **state which principle drove it and what the alternative would have
been** — one or two sentences, in the response (not as code comments). Example: "the repository
interface lives in Application because the dependency rule forbids Application knowing about
Npgsql; the alternative — injecting `DbContext` directly — would make the use case untestable
without a database." Never silently apply an architectural decision.

If a request would violate a rule above, say so before writing code, and propose the compliant shape.

## Where to look

| Question | File |
|---|---|
| What are we building, for whom | `docs/vision.md` |
| System shape, components | `docs/architecture/overview.md` |
| Layers, what goes where, ports & adapters | `docs/architecture/clean-architecture.md` |
| Threads, channels, ordering, locks, shutdown | `docs/architecture/concurrency.md` |
| Schema, indexes, partitioning, outbox | `docs/architecture/data-model.md` |
| Topics, event contracts, delivery semantics | `docs/architecture/messaging.md` |
| WebSockets, presence, scale-out | `docs/architecture/realtime.md` |
| Cache, invalidation, rate limits | `docs/architecture/caching.md` |
| Attachments, presigned uploads, MinIO/S3 | `docs/architecture/file-storage.md` |
| Ingress, load balancing, deploys, probes | `docs/architecture/edge.md` |
| Timeouts, retries, circuit breakers, bulkheads | `docs/architecture/resilience.md` |
| Who can do what — current gap, open decision | `docs/architecture/authorization.md` |
| Which repository, package boundary, cross-repo changes | `docs/architecture/repositories.md` |
| Target numbers / SLOs | `docs/architecture/nfr.md` |
| Why a decision was made | `docs/adr/` |
| Style, naming, errors, logging | `docs/conventions/coding-style.md` |
| Branches, MRs, rebase rules | `docs/conventions/git-workflow.md` |
| Anything involving a timestamp | `docs/conventions/date-and-time.md` |
| Test levels and what belongs where | `docs/conventions/testing.md` |
| HTTP/realtime protocol, versioning | `docs/conventions/api-design.md` |
| Folder layout, project naming | `docs/conventions/naming-and-structure.md` |
| How to run things, workspace layout | `docs/runbooks/` |
| What to build next | `docs/roadmap.md`, `docs/backlog/` |
| Available skills | `SKILLS.md` |

## Working agreements

- **Read before writing.** Check the relevant `docs/architecture/*` and any matching skill first.
- **One vertical slice per task.** Domain → Application → Infrastructure → Host → tests, complete.
  A slice that compiles but has no test is not done.
- **A decision worth arguing about becomes an ADR** (`docs/adr/`), added in the same change.
- **Docs are part of the deliverable.** If a change makes a doc wrong, fix the doc in the same change.
- Do not add a NuGet package without saying what it replaces and why hand-rolling is worse.
- Do not invent numbers, benchmarks, or "typical" production figures. Measure or stay silent.

## Commands

All verified by actually running them (`0-01`..`0-04`). Run from each repository's own root.

**`ago-platform`** and **`ago-chat`** (same shape in both):

```bash
dotnet restore <Solution>.slnx
dotnet format <Solution>.slnx --verify-no-changes   # CI runs this before build; fails fast
dotnet build <Solution>.slnx --no-restore -c Release
dotnet test <Solution>.slnx --no-build -c Release
```

`ago-chat` restores `Ago.Platform.*` from the local file feed `nuget.config` points at
(`C:\git\ago\.nuget-feed\`) — pack `ago-platform` into it first if it is empty:

```bash
dotnet pack Ago.Platform.slnx -c Release -o C:\git\ago\.nuget-feed
```

For a change spanning both repositories, the dev override swaps that for a `ProjectReference` into
`../ago-platform` (`docs/architecture/repositories.md`) — never left on in a merged branch:

```bash
AgoPlatformDevOverride=true dotnet build   # bash
$env:AgoPlatformDevOverride = 'true'; dotnet build   # PowerShell
```

**`ago-deploy`** — compose loop and cluster loop, both in `docs/runbooks/local-dev.md` and
`docs/runbooks/k8s-local.md`; not duplicated here since the runbooks carry the verified detail
(healthcheck timing, the NGINX Gateway Fabric install, known WSL2/cgroup issues).

**CI** (`.github/workflows/ci.yml` in both backend repos, `adr/0015`): the commands above, run by
GitHub Actions on every push and PR; `ago-platform` additionally packs and uploads a `.nupkg` on
`main`, and `ago-chat`'s CI packs `ago-platform`'s current `main` from source into a throwaway local
feed before restoring — there is no hosted registry yet.
