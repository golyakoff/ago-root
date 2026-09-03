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
9. **Ordinary commits, pushes, and opening PRs on feature branches may be done directly by the
   managing Claude Code session**, without asking first each time, once a slice's own done-when
   criteria are verified and the local build/test suite is green. This delegation is narrow:
   - It does not extend to background workers spawned to implement a slice — a worker still hands
     back a commit-prep block for the managing session to review and execute; it never runs
     `git commit`/`git push` itself.
   - **Never push directly to `main`.** Every change reaches `main` only through a PR the author
     merges by hand. Opening a PR is not merging it — **merging is always the author's action, no
     exception**, exactly as before this rule changed.
   - `git push --force`, `git commit --amend`, `git rebase` on an already-pushed branch, and
     anything else that rewrites history remain the author's exclusively — unchanged.
   - Draft commit messages never carry a `Co-Authored-By` trailer for an AI session — whoever is
     named in the local git identity is the author of record, regardless of who typed the command.
   (Decided 2026-08-23, after this had been running as a manager-session-drives-background-workers
   workflow for a while and the per-commit ask had become the actual bottleneck; scope is deliberately
   the managing session only, not every session or every worker, and merge stays manual regardless.)
10. **Work happens on a feature branch**, one branch per slice/backlog item. An MR is the branch
    *rebased onto `main`* with the full suite green **after** the rebase — never `main` merged into
    the branch (`docs/conventions/git-workflow.md`). "Rebased onto `main`" means `main`'s tip **at
    push time**, not at branch-cut time: `git fetch` and confirm `git merge-base HEAD origin/main`
    equals `git rev-parse origin/main` **before the first push**, and rebase while the branch is
    still local if it does not. After the branch is pushed a stale base is no longer rebasable by
    anyone but the author — it becomes close-the-PR-and-rebuild — so the check is cheapest exactly
    once, just before pushing.
11. **Time is UTC `DateTimeOffset`, always.** Store `timestamptz`, transport ISO-8601 with an
    explicit offset, render in the user's IANA zone when supplied and otherwise render UTC *labelled
    as UTC*. `DateTime` and `DateTime.UtcNow` are banned outside Infrastructure; time comes from
    `IClock`. Ordering never depends on a clock — it uses the server-assigned `sequence`
    (`docs/conventions/date-and-time.md`, `docs/adr/0011-*`).
12. **A background worker never spawns another agent.** The managing session may spawn workers; a
    worker may not spawn anything. A worker that believes its task warrants delegation **says so in
    its report and stops** — that decision belongs to the author, not to the worker and not to the
    managing session, and it is made by the author saying so explicitly rather than inferred from a
    worker's plan.
    (Decided 2026-09-02, after two briefs in one day produced agents that *organised* the work
    instead of doing it. One of them had already spawned a child the managing session did not know
    about, concluded nothing was running from the absence of a worktree, and told it to implement the
    task itself — putting two agents in the same worktrees at once. `ListAgents` answers "is
    something already running"; an empty directory does not. Cost is the other half of the reason:
    every spawn pays a full cold start rediscovering repository structure, and one measured wave of
    three workers cost roughly 840,000 tokens.)
13. **"Го по жире" is a standing request with fixed terms.** When the author says it, the managing
    session may run **up to three** background workers on `sonnet`, in parallel, **each in its own
    isolated worktree** — and opens their pull requests **strictly one at a time**.
    - **Three is a ceiling, not a target, and non-interference is the precondition.** Judging whether
      two items collide is the managing session's job before spawning anything: the same repository
      *file*, the same EF migration, the same shared index, or one item's output being the other's
      input all mean they do not run together. When in doubt, run fewer.
    - **Sequential PRs are the half that is easy to skip.** Two branches cut from the same `main` and
      opened at once means the second goes stale the moment the first merges, and a pushed branch with
      a stale base is close-the-PR-and-rebuild rather than a rebase (rule 10). Land one, then cut the
      next from the `main` that now contains it. `land-a-slice` already required this for the shared
      indexes; under this rule it applies to every PR in the wave.
    - Everything else stands unchanged: workers still never spawn anything (rule 12), never write
      history (rule 9), and hand back commit-prep blocks the managing session executes.
    (Agreed 2026-09-02, generalising what had until then been decided per-wave.)
14. **A ticket ends in an explicit state, and unfinished work always gets a number of its own.**
    - **Solved → close as done** (`gh issue close <n> --reason completed`). **Cancelled → close as
      won't-do** (`gh issue close <n> --reason "not planned"`). Passing no `--reason` silently means
      `completed`, so a cancelled ticket closed without the flag is recorded as *delivered* — the
      worst of the outcomes, because the queue then claims work exists that never happened.
    - **Never leave a ticket half-done.** Either finish it, or rewrite it to what actually shipped
      and carry the remainder out. A ticket rewritten to its delivered scope is closed as done — it
      is not "partly failed", it is a smaller item that succeeded.
    - **Carrying a remainder out means a *new number*, not a link.** When work is split off, it gets
      a new ticket in the code repository **and always a new item plus issue in `ago-root`.** Leaving
      it under the finished item's number is the failure this clause exists for: by the `NN-NN ·`
      title convention that prefix asserts "this *is* item NN-NN", so unfinished work ends up
      claiming the identity of a finished one, with no `ago-root` twin at all.
    - **Closing means closing every mirror.** Items are filed twice — in `ago-root` and in the
      repository they change — and closing one is not closing the item. This is part of merging, at
      the same moment as the roadmap and ADR-index sweep, not a later batch.
    (Decided 2026-09-02, from two misses in one day. First: `11-15` shipped, `ago-root#322` was
    closed, its twin `ago-calendar-console#27` stayed open, and `queue-audit.sh` — which then read
    `ago-root` only — reported a clean queue; it was found because the author asked. Second, found by
    the mirror-aware audit on its first run: `ago-calendar-console#26` was still titled `15-11 ·`
    after being split out of `15-11`. The tempting fixes were both wrong — closing it would close
    undone work, and reopening `15-11` would have re-widened an item that had been *correctly*
    narrowed to what it delivered. What was missing was a number, which became `15-12`.)

15. **One ticket, one thing. An "and" in a ticket is almost always a seam to cut along.**
    - **Treat the conjunction as the signal.** A title or scope joined by "and", or a scope that reads
      as a list, is the common shape of two tickets wearing one number. Split first and ask whether
      that was unnecessary afterwards — the reverse is much more expensive.
    - **The test is one promise that lands green — not whether the code is separable.** A ticket is
      one thing when it makes a single promise that is true or false as a whole, *and* closing it
      leaves the system passing its quality gates. Two things belong apart when they make **different
      promises**, not merely when they touch different files.
      - **A split that produces "the first breaks it, the second fixes it" is a bad split.** Every
        ticket must be able to close with the build, the suites and the gates green. If closing A
        leaves a gate red until B lands, then A and B are one ticket — that is the sharp, checkable
        form of this rule, and it catches over-splitting and dependent-splitting alike.
      - **Over-splitting is a real failure, not a safe direction to err in.** Two changes that are
        the *same* promise in different places — one symptom, one verification, one thing a reader
        would call finished — are one ticket even when the code is trivially separable.
      - Code-level independence ("different files", "neither calls the other") is about
        implementation coupling and answers a different question. It is not the test.
      - **The gate check is a veto, not a permission.** A split that fails it is wrong; a split that
        passes it is not thereby right. Where no gate would go red either way, the promise still
        decides — `#342` (rename the widget bundle to `widget.js`; its lazily-loaded chunk is named
        by a literal, so renaming one without the other reddens nothing) is one ticket because the
        promise is one: the widget's public files are named for what a person recognises.
    - **Why it costs**: a ticket with two halves cannot be closed honestly when one is done, so it
      either sits open with delivered work invisible inside it, or gets closed with the other half
      buried. Both are how work goes missing. It also forces one review to carry two arguments, and
      the author's review capacity is this project's actual bottleneck. Rule 14's third clause exists
      to clean up after exactly this; splitting up front is cheaper than splitting at close.
    - **When a ticket is already in flight and turns out to be two**, split it anyway: rewrite it to
      one half, file the other, and keep the two changes separable so each closes its own ticket.
    (Decided 2026-09-03, from `#339` — filed as "the calendar hosts have no schema guard **and** the
    migrator no database wait". Two mechanisms, two layers, two proofs, nothing shared but the
    repository and the reason they were both noticed at once: two promises, each landing green.
    Amended the same day by the opposite mistake. `#343`/`#344` — a hardcoded `en-GB` in
    `time/format.ts`, and one screen bypassing that file with a bare `toLocaleString()` — were split
    on the code-level test and should not have been. They are one promise, "the console shows dates
    correctly", and it shows: `#343` alone leaves `11-16`'s gate **red** on `admin-conversations`,
    so it cannot close green. That is what replaced "can they be finished separately" with "does each
    land green" as the test.)

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
| Rotating a secret, or reacting to one that leaked | `docs/runbooks/secret-rotation.md` |
| A Dependabot or vulnerability-scan finding, or why there is no SBOM | `docs/runbooks/vulnerability-response.md` |
| What to build next, in what order | The board: <https://github.com/users/golyakoff/projects/1> |
| Why it is next, and what a stage is for | `docs/roadmap.md`, `docs/backlog/` |
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
