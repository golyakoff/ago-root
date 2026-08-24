# Roadmap

Stages are ordered so that the project is demonstrable early and the hardest, most interview-relevant
work (Stages 4, 6, 7, 9) happens on a stable skeleton rather than during it.

Each stage lists its **goal**, **deliverables**, and **done when** — the last one is what a session
checks itself against before calling the stage finished. Stages are not time-boxed; they are
scope-boxed.

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

## Stage 9 — Prove the abstractions

**Goal:** the interview-winning demonstration that the ports are real.

Deliverables:
- `Ago.Platform.Messaging.Kafka` implementing the same port; the full suite green against it.
- `Ago.Chat.Infrastructure.MySql`; the full suite green against it.
- A short document listing every friction found (ordering scope, replay, `jsonb` vs `json`,
  `SKIP LOCKED` behaviour, offset/timestamp handling) — the honest list is the deliverable.

**Done when:** `Messaging:Provider` and `Persistence:Provider` switch the system with zero changes in
`Domain` or `Application`, proven by a CI matrix running both combinations.

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

**Done when:** a new account, site, and operator can be created end to end by a real visitor, with
zero seed-script involvement.

---

## Stage 11 — Widget customization

**Goal:** a site owner can make the embedded widget look like their own site, not a generic AGO one.

Deliverables:
- Per-site widget configuration: colors, styles/theme, position on the host page.
- Console surface to edit that configuration.
- Widget bootstrap reads and applies the configuration live - no rebuild or redeploy of the widget
  bundle needed per site.

**Done when:** a site owner changes color/position from the console and sees it reflected in the
embedded widget on their own page without touching code.

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

## Stages 15-19 — reserved for further AGO Chat and AGO Platform work

Not yet planned. Stage 14 (above) is the first item to actually use the range Stage 10 froze open
(2026-08-23); the rest stays reserved so later `ago-chat`/`ago-platform` work does not collide with
Stage 20's own number.

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
