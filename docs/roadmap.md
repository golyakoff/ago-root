# Roadmap

**A stage number is an identifier, not a position in a queue.** Stages 0-8 were built in numeric
order, and that shaped the early sequence deliberately: demonstrable early, with the hardest and most
interview-relevant work (Stages 4, 6, 7) landing on a stable skeleton rather than during it. From
Stage 9 onward the number stopped meaning order and nobody said so — Stage 9 was deprioritized in
place rather than renumbered, Stages 20 and 21 were numbered out of range on purpose, and within two
days of Stages 15 and 16 being written, four of their items had to be marked as coming first. Four
exceptions in two days is not an exception list; it is a sequence that disagrees with its own
numbering.

So the numbering is now what it always actually was — a stable name for a body of work, which
cross-references can point at without churn — and **the order lives in "What comes next" below**,
which is the section to read when the question is what to build (corrected 2026-08-25).

Each stage lists its **goal**, **deliverables**, and **done when** — the last one is what a session
checks itself against before calling the stage finished. Stages are not time-boxed; they are
scope-boxed.

---

## What comes next

The current order, most urgent first. Bands, not a strict queue: anything in a band can be picked up
before anything below it, and within a band the order is a judgement call rather than a dependency.

### Now — broken, or blocking something else

| Item | Why it cannot wait |
|---|---|
| `17-01` tenant-isolation proof | The enforcement is centralized and its core is proven, but the composition is not: handler tests use a fake permission checker, two route groups accept a client-supplied `siteId` on purpose, at least one belongs-to-site guard has no test, and nothing stops the next handler skipping the check. `12-02` is about to add a *legitimate* cross-tenant reader, after which a deliberate exception and a forgotten filter look identical |
| `15-01` Keycloak persistent user store | `start-dev`, no `KC_DB`, no volume: every runtime-created user is destroyed by the next pod restart. Stage 10's entire premise is runtime-created users |
| `10-05` transactional email | `verifyEmail: true` with `smtpServer: null` — registration is accepted and the mail can never be sent, so no real visitor can finish signing up |
| `16-01` personal-data map and residency | Not breakage, but two vendor questions due imminently (`10-05`'s provider, `15-02`'s backup destination) both move personal data somewhere, and answering either without the constraint is how a residency problem gets acquired |
| `5-14` + `17-02` the hub access token | Both SignalR clients print the negotiated WebSocket URL — token included — to the browser console on every connect (`5-14`, confirmed live). Whether the same URL also reaches the edge access log and the trace spans is unverified (`17-02`), and that is the half that would matter: a token on disk outlives one in a devtools pane |
| `6-09` release operator capacity on close | A live defect from `7-04`'s load run: an operator's usable capacity decays until their connection drops, so the waiting queue quietly stops being served |

### Soon — the current stage, and what the "Now" band leaves half-finished

`11-06` (the operator workspace — `11-05`'s design foundation landed 2026-08-25 with `adr/0030`, so
this is what is left of Stage 11 besides the notice field `16-04` adds later), `10-03` (console signup
UI, which only becomes real once `10-05` lands), `15-02` (backup and a restore drill), `15-03`
(alerting), `5-13` (presigned upload size never enforced by storage).

### After — in roughly this order, each already scoped

Stage 12 (owner admin panel), Stage 13 (billing — partly blocked, see below), the rest of Stage 15,
the rest of Stage 16, Stage 14 (AGO Inbox), Stage 20 (AGO Calendar), Stage 21 (the two products'
integration). Stage 9 stays deprioritized. Stages 17-19 hold security (`17-01` is its first item) and
operator-productivity work, neither fully scoped yet.

### Waiting on someone else's clock

Not work, and not blocked on effort — these have calendar latency that is not ours, so they are worth
starting earlier than the work that needs them:

- The **legal consultation** gating `16-04` and the whole `ago-business` legal block.
- The **email provider** (`10-05`) and the **backup destination** (`15-02`) — both the author's
  decisions, both now constrained by data residency (`16-01`).
- The **free-tier retention window** (`13-05`), which blocks two Stage 13 items and, per
  `personal-data.md`, is also the strongest privacy lever available.

### How this list is kept honest

It is updated when an item lands or when something genuinely jumps a band — not retroactively to
match what happened. If this list and reality disagree, this list is what is wrong. An item is only
moved into "Now" for a reason that can be stated in one sentence about present-tense breakage or a
dependency with a date; "it would be nice to do next" is what the "Soon" band is for.

---

## Stage 0 — Foundation

**Goal:** six repositories that build, publish and consume each other, plus the rules that keep them
honest — with no business code in them yet.

Deliverables:
- Repositories created and structured per `conventions/naming-and-structure.md`; junctions per
  `runbooks/workspace.md`.
- `ago-platform`: `Ago.Platform.Kernel` (`Result<T>`, `Error`, id primitives, `IClock`,
  `IIdGenerator` producing uuid v7) and `Ago.Platform.Hosting` with the `IProductModule` contract.
  `dotnet pack` into a local file feed; SemVer from the first version.
- `ago-chat`: solution consuming those packages through `nuget.config`, the documented
  `ProjectReference` dev override, and an empty `Ago.Chat.Module`.
- `Ago.Chat.Architecture.Tests` with the rules from `architecture/clean-architecture.md` — written
  **first**, and demonstrably failing when deliberately violated.
- `.editorconfig`, nullable, warnings-as-errors, central package management, in both backend repos.
- `ago-deploy`: docker-compose (Postgres, RabbitMQ, Redis, MinIO) and a Kustomize base plus `local`
  overlay for the Docker Desktop cluster.
- CI per repository: build, test, arch test on every branch; platform additionally packs and publishes.

**Done when:** `ago-chat` builds against a *published* platform package version (not a project
reference), `dotnet test` is green, `kubectl apply -k` brings up the infrastructure, and an
intentional layering violation fails CI.

---

## Stage 1 — One vertical slice, end to end

**Goal:** a visitor's message reaches an operator. Nothing scalable yet — the shape first.

Deliverables:
- Domain: `Site`, `Visitor`, `Operator`, `Conversation`, `Message` with real invariants.
- Use cases: `StartConversation`, `SendMessage`, `GetConversationHistory` (keyset).
- Postgres persistence with EF Core migrations; Dapper read store for history.
- `Ago.Chat.Api` with the two hubs, visitor token issuance, minimal auth for operators. "Minimal"
  means identity only, no authorization model yet - `architecture/authorization.md` is the open
  question this slice will make impossible to keep deferring.
- `IProductModule` and the host loading it — the platform/product seam exists from the first slice.
- Tests at every level, including the DST-boundary time test.

**Done when:** two browser tabs talk to each other through one API instance, history survives a
reload, and the whole path has tests that would fail if the layering were bypassed.

---

## Stage 2 — Durability: outbox, consumers, idempotency

**Goal:** an acknowledged message is never lost.

Deliverables:
- `outbox` and `inbox` tables; write-in-one-transaction discipline in every handler.
- `Ago.Chat.Worker` host, outbox dispatcher with `FOR UPDATE SKIP LOCKED` and poll-plus-notify.
- RabbitMQ adapter implementing the port from `adr/0006`, including retry/DLQ.
- Idempotent consumers; `messages` partitioning introduced here.
- Integration tests with Testcontainers, including "kill the dispatcher mid-batch".

**Done when:** the broker can be stopped and started under load with zero acknowledged-but-lost
messages, and duplicate delivery provably creates no duplicate rows.

---

## Stage 3 — Scale-out realtime

**Goal:** more than one Api replica, with no sticky sessions.

Deliverables:
- Redis connection registry, presence, heartbeats, TTLs (`adr/0007`, `adr/0009`).
- Targeted fan-out through the broker; per-node delivery consumers.
- Reconnect-and-resume protocol (`sequence`-based), jittered backoff in the client.
- Caching layer: `ICache` port, cache-aside for site config, stampede protection, TTL jitter,
  event-driven invalidation, `IRateLimiter` token bucket.
- Graceful shutdown: drain, readiness-vs-liveness split, `preStop`.

**Done when:** three Api replicas serve one conversation correctly, a rolling restart under load
costs only reconnects, and `FLUSHALL` on Redis degrades without corrupting anything.

---

## Stage 4 — Assignment engine (the concurrency centrepiece)

**Goal:** the contended path, done properly and provably.

Deliverables:
- Waiting queue, capacity model, assignment loop with `SKIP LOCKED` batch claiming.
- Optimistic-concurrency capacity enforcement; retries treated as normal outcomes.
- The Redis distributed-lock alternative behind the same port, for comparison.
- Release-on-operator-disconnect with a grace period.
- In-process pipeline: bounded channels, batch writer, `ConversationSequencer`.
- `Ago.Chat.Concurrency.Tests`: ordering, capacity, idempotency, shutdown, backpressure.

**Done when:** under sustained contention no operator ever exceeds capacity, no conversation is
double-assigned, ordering holds, and the stress tests pass repeatedly rather than usually.

---

## Stage 5 — The two frontends and attachments

**Goal:** something a person can actually use, and the file path.

Deliverables:
- Widget: TypeScript, Shadow DOM, small bundle, reconnect logic, `data-site` bootstrap, a demo host page.
- Operator console (framework decided here — React or Angular, recorded as an ADR). Console login is
  where operator authentication stops being deferrable - `architecture/authorization.md` records the
  working direction (OIDC) and the still-open authorization-model decision.
- Attachments end to end: presign, direct upload, verify, thumbnail consumer, orphan sweeper
  (`architecture/file-storage.md`).
- Per-site CORS from the database; per-site and per-visitor rate limits enforced.

**Done when:** a plain HTML page with one script tag holds a real conversation with file exchange
against the local cluster.

---

## Stage 6 — Outbound webhooks and resilience

**Goal:** the boundary with someone else's unreliable system, contained properly.

Deliverables:
- `Ago.Chat.Webhooks` host: tenant endpoint registration, signed deliveries, delivery log.
- `Ago.Platform.Resilience`: timeout, jittered retry, circuit breaker and bulkhead policies behind
  ports — configured per call site, never applied globally by reflex.
- Per-endpoint circuit breaker, per-tenant concurrency cap, layered timeouts, bounded retries, DLQ
  with the full request/response context (`architecture/resilience.md`, `adr/0013`).
- A fake CRM test harness with three personalities: hangs, 5xxs, disappeared.
- Tenant-visible delivery history, because a webhook system without one is unsupportable.

**Done when:** with a CRM that hangs for 30 seconds on every call, message ingest and delivery stay
inside their `nfr.md` targets — proven under load, not asserted. The breaker opens, the bulkhead
holds, and nothing retries in a hot loop.

---

## Stage 7 — Observability and load

**Goal:** turn every claim in `architecture/nfr.md` into a number.

Deliverables:
- OpenTelemetry traces spanning hub → handler → DB → outbox → broker → consumer → delivery.
- Metrics: RED per endpoint/hub/consumer, queue depth, channel occupancy, batch histogram, outbox
  lag, DLQ count, cache hit ratio, connections per node, assignment conflicts.
- Grafana dashboards checked into `deploy/`.
- Load scenarios: steady ingest, burst, connection storm, reconnect storm, assignment contention,
  attachment presign throughput, cold-cache stampede, pod-kill during load, and a hanging third-party
  endpoint (the bulkhead claim from Stage 6) — run via `Ago.Chat.LoadDriver`, a real `.NET SignalR
  client`, not k6 (k6 remained uninstallable in every unsupervised session that attempted these runs;
  see `load/reports/2026-08-24-*.md`).
- **A written report** in `load/reports/` with method, hardware, numbers, and what was tuned.

**Done when:** the report exists with real p50/p95/p99 numbers against the targets, and any target
that was missed is explained rather than quietly dropped. Done via `load/reports/2026-08-24-stage-7-
summary.md` — nine scenario reports at ~1-3% of `nfr.md`'s stated scale (one, pod-kill, did not run —
blocked by a tool permission denial), one real bug found (`6-09`, still open) and one Stage 6 regression
confirmed fixed (the webhook bulkhead).

---

## Stage 8 — Public demo deployment

**Goal:** a URL a recruiter can open.

Deliverables:
- `Ago.Chat.*` hosts switched to a minimal production base image before anything ships publicly
  (`8-00`).
- Deployment to a k3s VPS (chosen over a managed Kubernetes offering, `8-01`'s own ADR records why)
  under `*.reserve-me.ru` (`adr/0026`'s own "Post-decision update" - the domain actually purchased
  differs from that ADR's original recommendation); TLS; two independent seeded demo tenants
  (`8-02`, `8-05` - a second tenant added specifically to show live tenant isolation).
- A demo page with the widget plus a public operator console with a throwaway login, per tenant.
- README rewritten for the reviewer audience: what it is, the architecture in one diagram, the
  numbers from Stage 7, the ADR index, and an honest "what I would do differently" section.

**Done when:** a stranger with the link can hold a conversation with the operator console, and the
README answers "why" before they have to ask. **Done, live and verified** (2026-08-24) — every
item `8-00` through `8-05`.

---

## Stage 9 — Prove the abstractions (deprioritized 2026-08-24)

**Goal:** the interview-winning demonstration that the ports are real — `Ago.Platform.Messaging.Kafka`
and `Ago.Chat.Infrastructure.MySql`, each implementing the existing port, full suite green against
both, plus an honest friction report (ordering scope, replay, `jsonb` vs `json`, `SKIP LOCKED`
behaviour, offset/timestamp handling).

**Deprioritized, not cancelled as a design claim**: the author's own call, once Stage 8's public
deployment was live — this stage would only re-prove a boundary the ADRs (`0002`, `0006`, `0011`,
`0017`) already argue for from the abstraction's own shape, not from a second working
implementation. Real portfolio value sits ahead of it (Stages 10-14, 20-21) rather than in a second
broker/database adapter nobody downstream depends on. The four backlog items that were scoped for
it (`9-01`-`9-04`) were removed rather than left `ready` and stale — if this stage is ever picked
back up, it gets re-scoped fresh against whatever the platform looks like at that time, not against
a plan written before Stages 10-21 existed. Every ADR that cites "Stage 9" as where a provider swap
gets proven still means it — this note only changes *when*, not the underlying design claim.

---

## Stage 10 — Self-service signup

**Goal:** a visitor becomes an AGO Chat account holder without the author running a script.
Reprioritised ahead of AGO Ads (2026-08-23) — the author wants AGO Chat production-ready before the
second product; Ads itself moved to Stage 20 the same day, freeing Stages 11-19 for further AGO
Chat/AGO Platform work. Split (2026-08-23) from a single combined stage into four, in the order the
author actually wants them built — signup first, billing last, not bundled together. **AGO Ads was
replaced by AGO Calendar as the second product (2026-08-24)** — Stage 20 below is now AGO Calendar,
and Stage 14 of the range this note freed up is now AGO Inbox; the reprioritisation reasoning that
put Chat's own production-readiness ahead of the second product is otherwise unchanged, which is why
this note is corrected in place rather than rewritten.

Deliverables:
- Self-service account/tenant registration, replacing `1-05`'s seed-script-only provisioning: a
  visitor becomes an account holder with a first site and a first operator, without anyone running a
  script by hand.
- Everyone starts on the free tier - paid tiers aren't reachable yet, since billing (Stage 13) hasn't
  landed.
- A transactional email path (`10-05`, added 2026-08-25). Not in this stage's original scope, and
  discovered to be load-bearing for it: the realm ships `registrationAllowed: true` with
  `verifyEmail: true` and `smtpServer: null`, so Keycloak accepts a registration and then cannot send
  the verification mail (`SEND_VERIFY_EMAIL_ERROR ... email_send_failed`, found live and recorded in
  `runbooks/local-dev.md`). The account exists, the required action never lifts, the visitor is stuck.
  Email had been deferred by `10-01` and then again by `13-01`, each pointing at the other, with no
  item owning it - the same shape of chain the console's design pass turned out to be in.

**Done when:** a new account, site, and operator can be created end to end by a real visitor, with
zero seed-script involvement - and with no admin-API step standing in for a verification mail that
cannot be sent, which is what "end to end by a real visitor" has to mean here.

---

## Stage 11 — How both surfaces look

**Goal:** neither surface a person actually looks at is an accident. Two audiences, deliberately in
one stage: the site owner can make the embedded widget look like their own site rather than a generic
AGO one, and the operator gets a console that was designed rather than left as the markup the
scaffold happened to produce.

**Widened from "Widget customization" on 2026-08-24.** The console half was not in this stage's
original scope, and it is here for sequencing rather than theme: `5-06` deferred the design-system
choice to `5-07`, "where there is an actual UI to apply them to"; `5-07` built that UI and never made
the pass; and `10-03`, `11-02`, `12-03` and `13-04` each then wrote "reuse whatever form/button
styling `5-07` already established". What `5-07` established is `src/index.css` — seventeen lines
setting a font, a margin and a `max-width`. Four screens have now been specified against a design
that does not exist. Stage 12 and Stage 13 each add another console screen, so the pass either lands
here, at the end of the stage that already owns appearance, or those screens get built bare and
retrofitted afterwards. Inserting a new stage before Stage 12 instead would mean renumbering 12
through 14 and every cross-reference to them, for nothing but tidier grouping.

Deliverables:
- Per-site widget configuration: colors, styles/theme, position on the host page (`11-01`, shipped).
- Console surface to edit that configuration (`11-02`).
- Widget bootstrap reads and applies the configuration live - no rebuild or redeploy of the widget
  bundle needed per site (`11-03`).
- A console design foundation (`11-05`): tokens taken from the existing `ago-landing` identity rather
  than invented, a deliberately closed set of eleven components, an application shell with real
  navigation, loading/empty/error states as first-class, an accessibility floor, and the six existing
  screens retrofitted onto it. The dark theme `index.css` currently half-claims via `color-scheme:
  light dark` is dropped rather than left as a claim nothing honours (author's decision, 2026-08-24).
- The operator workspace itself (`11-06`): a three-region layout, a thread that reads as a
  conversation instead of `[sequence] authorKind: body`, a real composer, visible wait times, and a
  connection indicator instead of the raw hub state printed as text.

**Done when:** a site owner changes color/position from the console and sees it reflected in the
embedded widget on their own page without touching code; and an operator can work a shift in the
console without the interface being the hard part — verified live, by actually working conversations
through it, the same bar `5-07` held itself to.

---

## Stage 12 — Owner admin panel

**Goal:** the author, as platform owner, can see across every tenant - not just the per-site
visibility `5-08`'s "Admin" role already gives a site's own operators.

Deliverables:
- Internal operations view: every account/tenant, its tier, usage and abuse signals - the surface
  `adr/0023` already named as a reason React won the console framework decision, now actually built.
- Explicitly distinct from `5-08`'s site-scoped "Admin" role - this is platform-level, owner-only.

**Done when:** the owner can see every account, its tier, and its usage from one view, without
querying the database by hand.

---

## Stage 13 — Billing

**Goal:** turn a self-service account into a paying customer.

Deliverables:
- Entitlement enforcement matching the tiers and cost-containment criterion already decided in the
  private `ago-business` repo (seat count at minimum; attachments/history/site-count caps as those
  business decisions land) — DB-sourced checks, never cached, per `architecture/caching.md`'s "never
  cache what a write decision depends on."
- Account & billing management surface in `ago-console`: current tier, seats used, upgrade/downgrade.
- Subscription payment via ЮKassa: recurring/autopay billing, MIR-card-capable, checkout hosted by
  the provider so card data never touches AGO's own servers, payment-state confirmation via webhook
  through the existing outbox pattern (`architecture/messaging.md`) rather than trusting the
  redirect alone.

**Done when:** a real card can subscribe a self-registered account to a paid tier through ЮKassa, and
entitlements enforce that tier's limits.

---

## Stage 14 — AGO Inbox: channels and always-on responses

**Goal:** a visitor can reach AGO Chat through more than the embedded widget, and gets a real response
even when no operator is available - without any of this becoming a third product. Placed here, first
in the range Stage 10 freed up for further AGO Chat work, because it genuinely is further AGO Chat
work: `adr/0027` settles that its channel-routing target is AGO Chat's own `Operator`, so it belongs in
`Ago.Chat.*`, not a new repository, and nothing in its own scope depends on AGO Calendar existing yet
(unlike Stage 21, which does and is sequenced after Stage 20 for exactly that reason).

Deliverables:
- A new domain concept - an external channel identity (which external chat-id/phone-number maps to
  which visitor/conversation) - and a channel-adapter port behind `Ago.Platform.Resilience`'s existing
  timeout/retry/breaker/bulkhead mechanism, reused unchanged per provider (`14-01`).
- Two concrete channel adapters that need no legal or reliability spike first: MAX, chosen deliberately
  as the first one built (an open Bot API, no known regulatory friction, `14-02`), and SMS (`14-03`).
- Offline auto-reply: a tenant-toggleable, off-by-default scripted keyword reply for when no operator is
  available, on any connected channel including the widget itself (`14-04`).
- Telegram and WhatsApp explicitly gated behind their own spike/legal-review prerequisites, not built
  speculatively ahead of either (`14-05`, blocked).

**Done when:** a real message sent via MAX or SMS reaches an operator through the same console queue a
widget conversation already does, and a visitor gets an automatic reply when no operator is online, on
at least one connected channel - proven live, the same bar every other stage's "done when" already
holds itself to.

---

## Stage 15 — Operational readiness

**Goal:** the public deployment stops being a thing it would be acceptable to lose. Stage 8 made it
public; Stage 10 invites strangers to keep their own accounts and conversations in it. The stage that
closes the gap between those two facts did not exist until now (added 2026-08-24).

Every deliverable below is already written down somewhere in this repository as an explicit "out of
scope, because this is a demo cluster" — `7-02` and `7-03` on alerting, `8-01` on alerting and on
continuous deployment, `2-01` on outbox pruning, `2-06` on dropping old partitions. Each of those was
honest when written. This stage is where that reason expires, and it deliberately takes the deferrals
rather than quietly leaving them as permanent notes.

Deliverables:
- A Keycloak user store that survives a pod restart (`15-01`). It does not today: `start-dev`, no
  `KC_DB` anywhere in `ago-deploy`, no volume at its data directory — so every runtime-created user
  lives in an ephemeral H2 file inside the container layer and is destroyed by any restart. Only
  realm-imported objects come back. Stage 10's whole premise is runtime-created users, which makes this
  a prerequisite of Stage 10 being true in production rather than a piece of hygiene.
- Backup of every durable store, off the node, and a **restore that has actually been performed**
  (`15-02`) — one node, local-path volumes, and nothing copied anywhere else today.
- Alerting rules that fire and a channel that reaches a person (`15-03`), each rule proven by making it
  fire, each with a one-line "what to check first".
- A retention *mechanism* — bounded-batch pruning of published outbox rows, dropping old `messages`
  partitions, trimming the webhook delivery log (`15-04`). Deliberately the mechanism only: the
  free-tier history window is a product decision that stays with `13-05`, and this stage must not
  become that decision by shipping a default the product then inherits.
- Deliberate capacity: measured usage, PVC sizes chosen rather than inherited from a local Docker
  Desktop cluster, headroom arithmetic, and a **deliberate disk-full test** whose observed behaviour is
  written down (`15-05`).
- A real image registry, tagged images, and a rollback proven by performing one (`15-06`) — replacing
  build-on-the-VPS-and-import, which leaves no previous version to roll back to and gives a rebuilt
  cluster nothing to run.
- Two open defects re-homed here rather than left belonging to no stage: `5-13` (a presigned upload's
  size ceiling is never enforced by storage — the one path by which a stranger can write unbounded
  bytes to a shared 2Gi volume) and `6-09` (operator capacity is released only on disconnect, so a
  live operator's usable capacity decays until their connection drops).

**Done when:** the deployment can lose its node and come back from backup with the data intact — proven
by a restore that was performed, not designed; a self-registered account survives a redeploy; nothing
in the database grows without bound; a broken deploy can be rolled back to the previous tag; and every
alert rule in the set has been made to fire on purpose. No item in this stage is done on the strength of
a manifest that looks right — this is the stage where "verified means actually run" applies hardest,
because everything it builds only matters on the day it is needed.

---

## Stage 16 — Personal data: erasure, export, and knowing what is held

**Goal:** the project can say what personal data it holds, remove it on request, and hand it over on
request. None of those three is possible today — a repository-wide search finds no account deletion,
no export, and, until this stage's own `personal-data.md`, no inventory to check either against.

Two facts frame this stage, and they point in opposite directions (added 2026-08-25). Almost none of
this data is AGO's own: the operator profile is the small part, and the bulk is `messages.body` —
free text typed by a visitor on somebody else's site, which a support product exists to store and
cannot design away. But erasure is nevertheless tractable, by earlier decisions that were not made
for privacy reasons: `MessageAccepted` carries no message body and webhook payloads carry none either,
so the outbox and the delivery log hold no copies. Content lives in two places, not eight.

Deliverables:
- `architecture/personal-data.md` — what is held, where, why, and how it is removed; plus data
  residency as a standing constraint on vendor choices rather than a fact rediscovered per item
  (`16-01`, **pulled ahead of this stage** — see the Order section below).
- Tenant account deletion and per-conversation deletion on a visitor's request, reaching every store
  in that map, as resumable Worker jobs and proven by a test that asserts emptiness across Postgres,
  MinIO and Keycloak (`16-02`).
- Tenant data export — streamed, rate-limited, and provably unable to reach another tenant's data
  (`16-03`).
- A tenant-configurable processing notice in the widget, and an ADR recording the controller/processor
  split behind it: AGO answers for its own account holders, and acts on the tenant's instruction for
  their visitors' conversations (`16-04`).
- The two stores nobody has looked inside — traces and logs — audited against real traffic, edge
  access-log retention defined, and an incident procedure that depends on `15-03` actually detecting
  things (`16-05`).

Deliberately not here: the legal determinations. Whether a notice suffices or consent is required,
what the published policy and offer say, the processing clause in the tenant agreement, and whether a
given incident is notifiable — all belong in the private `ago-business` repository and need a lawyer,
the same gate `ago-business` already applies to Meta's Business API. This stage builds the mechanisms
any of those answers would need and stops short of asserting which answer is right.

Also decided here rather than left implicit: **no operator avatar** (author, 2026-08-25). An image of
a person's face is a further category of data plus another upload path with its own deletion, quota
and moderation surface, for a benefit initials already provide.

**Done when:** a tenant can delete their account and everything in it, and prove it is gone; a tenant
can export their data; the widget can carry a notice the tenant controls; and `personal-data.md`
describes the system as it actually is, with no unverified row left in it.

---

## Stage 17 — Security, starting with the tenancy claim

**Goal:** the security properties this system asserts are proven rather than asserted. Opened
2026-08-25 with one item, deliberately: the tenancy boundary, which is both the highest-damage
failure available here and the loudest claim the project makes about itself.

`vision.md` says it plainly — "Every piece of data is scoped by `site_id`; this is a multi-tenant
system from day one because retrofitting tenancy is the classic portfolio-project failure." An audit
run while scoping `17-01` (2026-08-25) found that claim to be in better shape than a quick look
suggests and less proven than it should be, which is a different problem from the one this stage was
opened expecting. Enforcement is centralized in one port and that port's real implementation has an
integration test proving it refuses a role belonging to another site. What is missing is proof of the
*composition*: handler tests drive a fake checker, two route groups accept a client-supplied `siteId`
by deliberate design, at least one belongs-to-site guard has no test covering it, and nothing makes
the next handler prove itself at all. On a deployment that is live and open to self-registration, that
gap is one refactor away from one shop reading another shop's conversations — and `12-02` is about to
introduce a *deliberate* cross-tenant reader for the platform owner, after which nobody can tell
"crossing tenants on purpose" from "forgot the filter".

Deliverables:
- `17-01` — every tenant-scoped operation proven to reject a caller from another tenant, and a
  systematic guard so a new one cannot be added without that proof, in the spirit of the arch tests
  that already make layering violations fail rather than rely on review.
- `17-02` — a definite answer to whether a live bearer token is persisted server-side. `5-14` (Stage 5,
  where the finding was made) fixes the browser clients that print it; this item checks the edge access
  log and the trace spans, neither of which has ever been looked at, and neither of which is covered by
  the API's own logging configuration being clean.

Named, not yet scoped, and explicitly *not* bundled into `17-01`: secret handling and rotation,
dependency and container scanning, VPS and cluster hardening, authentication bypass and token
handling review, and abuse controls beyond the rate limits `3-05` already ships. Each is real, none
is the tenancy boundary, and folding them together would mean shipping none of them properly.

**Done when:** for the first item, no tenant-scoped operation lets a caller from another tenant reach
anything, and that is enforced by something that fails automatically rather than by remembering.

---

## Stages 18-19 — reserved for further AGO Chat and AGO Platform work

Not yet planned. Stage 14 was the first item to use the range Stage 10 froze open (2026-08-23),
Stage 15 the second (2026-08-24), Stage 16 the third and Stage 17 the fourth (both 2026-08-25); the
rest stays reserved so later `ago-chat`/`ago-platform` work does not collide with Stage 20's own
number. One named candidate is already waiting: operator-productivity work — canned responses, search
across conversations, transfer between operators, notes and tags, shortcuts, notifications — named in
`11-06`'s out-of-scope as wanting a stage of its own rather than being a tail of a stage about
appearance.

---

## Stage 20 — AGO Calendar: the second product

**Goal:** prove the platform claim by building on it, not by asserting it - with a real product this
time, not a load-shape exercise (`vision.md`; replaces AGO Ads in this slot, 2026-08-24, `adr/0027`).

Deliverables:
- A new repository, `ago-calendar` (`Ago.Calendar.*`), consuming `Ago.Platform.*` packages exactly the
  way `ago-chat` does - own hosts (`Ago.Calendar.Api`, `Ago.Calendar.Worker`), own arch tests, no
  `ProjectReference` into `ago-chat` ever (`20-00`).
- Domain: `Tenant`, `Worker`, `Service`, `Calendar`, `Customer`, `WorkingHoursRule`, `Event` - `Event`
  is the one real row a booking transitions through (`Available → PendingConfirmation → Booked`, or
  `Cancelled`/`NoShow`), never a computed slot (`20-01`).
- Availability materialised in advance from each `WorkingHoursRule` out to a rolling horizon, with
  already-materialised days directly editable by the tenant rather than described as exceptions
  against the rule (`20-02`).
- Booking as an atomic compare-and-set claim on an `Available` row, with a real customer lead card
  upserted by phone number, no account (`20-03`).
- A periodic confirmation-sweep job flipping expired `PendingConfirmation` rows to `Booked` - the same
  architectural shape as `Ago.Chat.Worker`'s own `ConversationAssignmentJob`/`OutboxDispatcher`, not a
  new mechanism - plus operator reject, manual cancellation, and a no-show flag, all through one shared
  pending-bookings queue across a tenant's operators (`20-04`).
- SMS booking-confirmation delivery through a new `ISmsSender` port and an outbox-published integration
  event, vendor choice left as a real, named open question rather than an invented number (`20-05`).
- A tenant/operator console and a public, embeddable booking widget, reusing AGO Chat's own per-site
  CORS and Keycloak/OIDC patterns rather than inventing new ones (`20-06`).

**Done when:** both products run in the same cluster from the same hosts, a real booking can be made
and confirmed end to end against the local cluster, and the diff against `Ago.Platform.*` shows the
platform barely changed - every extension point that *was* needed gets written down, because that list
is the honest measure of how good the platform boundary was.

---

## Stage 21 — AGO Inbox × AGO Calendar: unattended booking and the unified queue

**Goal:** the two hard integration questions Stage 14 and Stage 20 each named but deliberately did not
solve on their own, now that both products actually exist to integrate. Sequenced after both because
it structurally depends on both - unlike Stage 14, which needed neither Calendar nor a later stage to
ship for real.

Deliverables:
- **Unattended booking through a channel with no rich UI** (`21-01`) - a visitor reaching AGO
  Calendar's own booking flow from plain SMS or a bare-buttons Telegram bot, with none of the widget's
  slot-grid UI available. Genuinely unsolved, on purpose: a step-by-step text Q&A tree, a
  channel-adaptive UX, and free-text natural-language understanding are three real candidate
  directions, none chosen here - this item stays `blocked` until the author picks one, rather than
  guessing.
- **A real unified operator queue across AGO Chat and AGO Calendar** (`21-02`) - `adr/0027` deliberately
  left this as deferred integration work rather than a structural consequence of a shared `Operator`
  entity; this item is where the actual stitching mechanism (console-side dual-API merge, or a
  lighter cross-product notification path) gets decided and built, not before.

**Done when:** both open questions above have a real, argued answer recorded (an ADR for each, since
both are genuine "a reviewer would ask why" decisions per `adr/README.md`), and at least one of them
ships end to end against the local cluster.

---

## Guardrails for all stages

- No stage is "done" with a red arch test, a skipped concurrency test, or a doc the code contradicts.
- Performance claims come from `load/`, never from intuition.
- Every stage that makes a real decision leaves an ADR behind.
- Scope creep goes to `docs/backlog/`, not into the current branch.
- A stage number never means "next". "What comes next" at the top of this file does, and it is
  updated when the work moves rather than afterwards.
