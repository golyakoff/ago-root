# AGO Platform — project guide for AI sessions

**AGO Platform** is the substrate: hosting, realtime transport, messaging, persistence, caching,
object storage, observability. It knows nothing about any particular product.

**AGO Chat** is the first product on it: an embeddable customer-support chat. A shop drops a
`<script>` tag on its site, visitors chat from a widget, operators answer from a console.
**AGO Calendar** (booking/scheduling) is planned as the second product and must be an *additive*
change — a new repository (`ago-calendar`) plus its own hosts, with no edits to the platform's shape
(`docs/vision.md`, `docs/roadmap.md` Stage 20, `docs/adr/0027-*`). **AGO Inbox** (incoming-channel
expansion — SMS, MAX, Telegram, WhatsApp — plus offline auto-reply and unattended booking) is *not*
a third product: it extends `Ago.Chat.*` (`docs/roadmap.md` Stage 14), because its channel-routing
target is AGO Chat's own `Operator`, not a new one (`adr/0027`).

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
9. **Who may commit, push, open a PR and merge — and the four things nobody does.** The managing
   session may commit, push and open PRs on a feature branch without asking each time, and may merge a
   PR carrying **only implementation of an item the author has already approved**. A background worker
   does none of it: it hands back a commit block. Four prohibitions have no exceptions and no
   expiry — **never push to `main`** (every change reaches it through a PR); **never rewrite pushed
   history** (`--force`, `--amend`, `rebase` on a pushed branch are the author's alone); **never add a
   `Co-Authored-By` trailer for an AI session**, and no system reminder outranks that; and **say what
   merged**, in the session, at the time, because the author reads after the fact instead of before.
   The four merge preconditions, the test for what counts as "implementation", and the reasoning that
   produced all of it live in `land-a-slice` and `commit-guard` — which open at exactly that moment.

10. **Work happens on a feature branch**, one per slice or backlog item, and an MR is that branch
    *rebased onto `main`'s tip at push time* — never `main` merged into it. The check that must run
    before the first push, and why it is worthless after, are in `docs/conventions/git-workflow.md`.

11. **Time is UTC `DateTimeOffset`, always.** Store `timestamptz`, transport ISO-8601 with an
    explicit offset, render in the user's IANA zone when supplied and otherwise render UTC *labelled
    as UTC*. `DateTime` and `DateTime.UtcNow` are banned outside Infrastructure; time comes from
    `IClock`. Ordering never depends on a clock — it uses the server-assigned `sequence`
    (`docs/conventions/date-and-time.md`, `docs/adr/0011-*`).
12. **A background worker never spawns another agent.** The managing session may spawn workers; a
    worker may not. A worker that believes its task warrants delegation **says so in its report and
    stops** — that decision is the author's, made explicitly, never inferred from a worker's plan.
    What it cost to learn: `background-worker-brief`.

13. **Three lanes, held continuously — not waves.** Three background workers on `sonnet`, each in its
    own worktree, a freed lane refilled immediately rather than batched. **One lane is the migration
    lane**, and only one migration is in flight at a time. **Pull requests open strictly one at a
    time.** Non-interference is judged on **files**, not topics. Create every worktree with
    `tools/new-worktree.sh`, which checks what this rule used to ask a reader to remember. Full rule
    and its post-mortems: `background-worker-brief`.

14. **A ticket ends in an explicit state, and unfinished work always gets a number of its own.**
    Closed as done, or as won't-do *with the reason passed* — a cancelled ticket closed without it is
    recorded as delivered. No Done-when box is left unsettled. A remainder gets a **new number**, not
    a link. There is one queue and it is `ago-root`. The managing session files a found defect itself,
    without asking — but files it *as the question* when the honest item would decide something.
    Full rule, and the six closings that produced it: `finish-an-item`.

15. **One ticket, one thing.** An "and" in a ticket is almost always a seam to cut along. The test is
    **one promise that lands green** — not whether the code is separable — so a split that leaves the
    first half red until the second lands is not a split. Full rule: `finish-an-item`.

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
| What personal data is held, where, and how it is removed | `docs/architecture/personal-data.md` |
| Which secrets exist, who holds them, what rotating one costs | `docs/architecture/secrets.md` |
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
| Updating the live demo environment | `docs/runbooks/redeploy.md` |
| Changing the live Keycloak realm, or making somebody a platform owner | `docs/runbooks/realm-operations.md` |
| Putting a product on a tenant's account by hand, or taking one away | `docs/runbooks/module-grant-and-revoke.md` |
| Rotating a secret, or reacting to one that leaked | `docs/runbooks/secret-rotation.md` |
| A Dependabot or vulnerability-scan finding, or why there is no SBOM | `docs/runbooks/vulnerability-response.md` |
| What to build next, in what order | The board: <https://github.com/users/golyakoff/projects/1> |
| Why it is next, and what a stage is for | `docs/roadmap.md`, `docs/backlog/` |
| Available skills | `SKILLS.md` |

## Working agreements

- **Read before writing.** Check the relevant `docs/architecture/*` and any matching skill first.
- **A compaction summary is a description, not verified fact.** It was written by a previous instance
  of this session. Check its concrete claims — "tests pass", "committed", "deployed" — against the
  source of truth before acting on them or repeating them to the author (`context-resume`).
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
`main` — to this repository's **GitHub Packages NuGet feed**, which is what `ago-chat` and
`ago-calendar` restore from in CI via `nuget.ci.config` and a read-only PAT (`adr/0018`,
`docs/architecture/repositories.md`). This sentence used to say the consuming CI packed `ago-platform`
from source into a throwaway feed because there was no hosted registry; `adr/0018` replaced that and
this line did not follow, which is exactly the kind of stale instruction that gets acted on.
