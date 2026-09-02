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

The current order, most urgent first. **The "Now" table below is a queue: work straight down it.**
The bands after it are looser — anything in a band can be picked up before anything below it, and
within those the order is a judgement call rather than a dependency.

Renumbering the stages to make the numbers themselves the queue was considered and declined
(2026-08-25). It would have been cheaper than expected — 32 backlog files and about 330 references,
all in this repository, and *zero* in any code repository, because unbuilt work has no code citing it.
It was declined because renumbering alone would not have produced a queue: stages are not sequenceable
as wholes, since `15-01` is broken today while `15-04` is future work and both sit in Stage 15. Making
the numbers a queue would have meant re-partitioning items into new stages, which buys an ordinal at
the cost of each stage reading as an argument rather than a bucket. The order lives here instead, and
a stage number stays a name.

### Now — in this order

Row order is the queue. It is not a dependency chain: nothing here blocks anything below it except
where the row says so.

**Deepened and reordered 2026-08-25**, on the author's call that the backlog had been circling
operational work while two whole products sat scoped and unbuilt. Checking that: `20-00`-`20-06` and
`14-01`-`14-04` are all `ready` — eleven items, fully written, waiting. Nothing needed planning; the
list needed ordering.

**This reverses the ordering argued earlier the same day, and the reason is that the situation
changed.** That argument was made while the firewall was open, Keycloak was losing users on restart,
signup could not complete and three live defects were open. All of that is now closed or in progress.
What remains of the safety work is *insurance*, and insurance has a low marginal return on a
deployment with no customers — whereas `20-00` is the only item in the entire backlog that tests the
claim every ADR rests on. The one piece of ops work kept high is `15-06`, and only because Calendar is
about to double the deploy surface that is already the weak point.

**Five scheduling-tool items inserted above `20-10`/`20-11`, 2026-09-01**, on the reasoning that
`20-10` and `20-11` harden a booking flow no real tenant can populate yet. AGO Calendar has no way for
a shop to keep a staff list or describe a shift pattern from the console, so the first live client
cannot fill a single day of availability - verifying the phone of a booking that cannot be made is
insurance on an empty building. The ordering is one edit to reverse if that judgement is wrong.

Three items sit parked below the table rather than in it, because they cannot be started.

| # | Item | Why here |
|---|---|---|
| 1 | `20-20` make AGO Calendar deployable, and deploy it | **The largest gap between the product as built and the product as usable.** Fifteen Stage 20 items are done and none of them runs anywhere: no Dockerfile for either host, no image-publishing job, no migrator, no manifest ever written in `ago-deploy`. Calendar's schema has no way to come into existence outside a test fixture. Every other Stage 20 item is unverifiable by hand until this lands, which is why it goes above work that is merely unfinished |
| 2 | `15-11` rendered UX gate, and the screenshots that fall out of it | Two of the three defects that reached the live deployment and were found by hand — an input one character wide on mobile, an error message dark grey on dark blue — are **measurements**, not opinions, and neither is catchable in jsdom because it has no layout engine. The same run produces the screenshots the delivery digest currently lacks, and it can photograph the calendar console **without waiting for `20-20`**, because it renders from source rather than from the stand |
| 3 | `10-03` console signup UI — **walk it, do not build it** | **Re-read 2026-09-02 and its urgency was understated.** This is not a nice-to-have: it is the *only* path by which a real tenant can come into existence. `POST /api/v1/sites` binds the new site to the **caller's own** token `sub` and cannot provision anybody else; there is no seed script in `ago-chat`; and `12-04` deliberately barred the platform owner from registering a site. Owner endpoints only read. So there is no interface for provisioning a customer by hand, and the first client's very first act will be this flow. Nothing needs building — the code shipped in `ago-console` `ead191e`. The one open Done-when is a human walking Keycloak's registration form end to end, which no session here can do because it means typing a password. **The author should walk it before the client does**; day one is the worst possible moment to find out it is broken |
| 4 | `10-06` the tenant never learns how to install the widget | **Found 2026-09-02 while preparing the `10-03` walkthrough**, by asking what happens *after* signup succeeds. The answer is nothing: the console shows no `<script>` snippet anywhere, never even fetches `publicKey`, and no API endpoint returns a site's key to the operator who owns it — the only occurrences are on the visitor side, where a key is consumed. So a real tenant finishes signup with a working account and no way to connect it to her shop. Both halves are missing, endpoint and screen |
| — | `10-05` transactional email | **In progress elsewhere.** Server side built and verified, PTR granted, handed to a development session. Listed so nothing is started against it twice |
| — | `7-10` load run on the provisioned server | **Deprioritized 2026-08-27** by the author, not abandoned. Stage 7's numbers stay honest as they are - measured on a workstation, labelled as such - and the run needs a decision that has been pending for two days: the live demo, or a throwaway node paid for by the hour. Neither the item nor the server has changed; it stopped being the most valuable next thing |

### Soon — folded into the queue above, 2026-08-25

This band held its own ordered list until the queue was deepened to thirty-three, at which point the
two described the same thing in two places — the failure this file has already corrected twice, once
for ordering and once for the pulled-ahead list. Everything that was here is in the table above, in
position, with its reason.

What belongs here now is only what is genuinely *not* queued and not parked: nothing. When the queue
drains past the point where thirty-three entries is more list than anyone reads, this band comes back
as the tail of it rather than as a second opinion about it.

### After — in roughly this order, each already scoped

Stage 13 (billing — partly blocked, see below), the rest of Stage 15, the rest of Stage 16, Stage 14
(AGO Inbox), Stage 20 (AGO Calendar), Stage 21 (the two products' integration). Stage 9 stays
deprioritized. Stages 17-19 hold security (`17-01` heads the queue's tail above, the rest is scoped)
and operator-productivity work, not yet scoped.

Stage 12 left this list on 2026-08-25, finished.

### Waiting on someone else's clock

Not work, and not blocked on effort — these have calendar latency that is not ours, so they are worth
starting earlier than the work that needs them:

**Completed 2026-08-25**, because this list had three entries while six decisions were outstanding,
and the missing three gate a whole set rather than a single item. Sorted by what they hold up:

- The **email provider** (`10-05`) — the most urgent, because `10-05` sits in the queue above and will
  reach the provider question mid-item. Constrained by data residency (`16-01`).
- ~~The **backup destination**~~ — **decided 2026-08-25**: the author's own machine, pulled over the
  SSH access that already exists. No monthly bill while there is no revenue to justify one, no SFTP
  daemon (SSH already is one, and adding a service would reopen surface `17-05` closed the same day),
  and the copy that leaves the host is what makes it a backup at all — the dump on the VPS is staging.
  It also inherits an obligation nobody had noticed: those pulled copies are personal data on a
  personal disk, so they expire on the same window the privacy policy states, or `16-02`'s "deletion
  is complete when the last backup ages out" is not true.
- The **legal consultation** the whole `ago-business` legal block needs — no longer gating `16-04`
  itself (`adr/0076`, shipped: the mechanism does not wait for the confirmation, only the exact wording
  a tenant is told does). The longest calendar latency of anything here and the one with no substitute,
  which is why it is worth starting before the work that needs it rather than when it blocks.
- ~~**Four subscription-lifecycle questions**~~ — **answered 2026-08-25** (`ago-business`'s
  `decisions/0006`), and `13-03` is unblocked. Failed charge: retries for roughly a week with full
  access retained, then Free. Cancellation: paid until the period ends, no refund. Mid-cycle:
  upgrades immediate and charged, downgrades at renewal with no credit — which removes credit
  accounting entirely, since ЮKassa has no balance concept. More operators than seats: nothing is
  deleted and nobody is chosen for the customer, the owner assigns the seats — one behaviour covering
  both the voluntary downgrade and the involuntary drop to Free, because in the second the customer is
  by definition not answering. `13-01` gains seat assignment and operator removal as a consequence.
- **What "site-count cap" means** (`13-05`): the identity-correlation problem `13-01` already named, or
  a genuinely new feature letting one paying account hold several sites. `10-02` deliberately rejected
  an `Account` aggregate above `Site`, so the second reading reopens that decision — which is exactly
  why the item refuses to guess between them.
- **The attachment-storage byte cap** (`13-05`) — partly a decision and partly a measurement: the shape
  (per tier, per seat, or flat per site) is a product call available now; the number waits on `15-05`
  like the retention window did.

What this list has stopped being is a footnote. Two days ago the bottleneck was scope — items were
unwritten and work could not start. It is now the other way round: nearly everything ahead is scoped,
and what stands between the current set and the next one is six answers, four of which need nothing
but an afternoon and a decision.
- ~~The **free-tier retention window**~~ — **decided in shape 2026-08-25** (`adr/0031`): time-boxed,
  per tier, via an immutable retention class in the partition key, archived rather than deleted. What
  is left is the window's *length*, which is no longer waiting on anyone's decision — it waits on
  `15-05` measuring real storage growth, which is ordinary work in the "Soon" band. `13-06` builds the
  mechanism meanwhile.

### How this list is kept honest

It is updated when an item lands or when something genuinely jumps the queue — not retroactively to
match what happened. If this list and reality disagree, this list is what is wrong.

**An item appears in exactly one place.** Putting it in the table removes it from "Soon" in the same
edit — never both (author's rule, 2026-08-25). This is the same failure this file has now corrected
three times: the pulled-ahead list, the Soon band's own ordering, and the Soon band again after the
queue was deepened. Two lists describing the same order do not stay in agreement, and the one nobody
is reading is the one that goes stale and then misleads.

When a row is closed, **delete it** rather than striking it through or moving it to the bottom with a
timestamp, and renumber the rest — the numbers are positions, not identifiers. The reasoning, since the
question came up on 2026-08-25 and will again: closing is already recorded in three places — the
backlog item's own `Status` line with its date and merge reference, the stage section, and git history.
A fourth copy inside the queue differs from those three only in that it will eventually disagree with
them, which is the same failure that made the ordering live in two places once before. A queue answers
one question: what to take next. Everything else about it is written down more accurately elsewhere.

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
blocked by a tool permission denial), one real bug found (`6-09`, fixed 2026-08-25 — its own
`assignment-contention` re-run is still owed, on a database no other session is writing to) and one
Stage 6 regression confirmed fixed (the webhook bulkhead).

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

**Two items added afterwards, 2026-08-25**, from a consequence of "a public operator login" that the
stage never stated: everyone who opens the console is the *same* operator, so every conversation
started from a demo page is readable by every stranger looking at the same time, and capacity, unread
counts and the queue are shared state between them.

- `8-06` — say so on the demo pages and on the way into the console. Two lines of copy, and the only
  control that works before somebody types something real into a chat box.
- `8-07` — mint demo credentials on request, expiring in about a day, so two viewers are two
  operators instead of two windows onto one inbox (author's decision, 2026-08-25). It reuses
  `10-02`'s registration bootstrap to create and `16-02`'s deletion to expire — which also gives
  erasure its first continuous consumer, exercised daily against real data rather than once by a
  test. And it needs no mail, since minted credentials are shown on screen, so it is one of the few
  things currently queued that can ship while `10-05` is still open.

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
- Behaviour tests for both frontends (`11-08`, added 2026-08-25). The two TypeScript repositories
  test only what needs neither a DOM nor a network — the reconnect primitives and a few pure
  functions — because `conventions/testing.md` described only .NET and said nothing about either of
  them. Two of six repositories were outside the document governing testing, and what got written was
  whatever a backend instinct recognised as testable. The convention now has a frontend section, and
  this item is the four behaviours worth protecting under it.
- The login page (`11-07`, added 2026-08-25 after the rest of the stage shipped). Noticed only once
  the designed console was live on the public deployment: the path runs from a landing page in Manrope
  and Unbounded, through Keycloak's stock theme with no AGO identity at all, into a console that was
  deliberately designed. The middle screen is the first one an operator or a self-registered account
  holder actually sees, and it was missed because it lives in a different repository and belongs to a
  component nobody thought of as ours.

**Done when:** a site owner changes color/position from the console and sees it reflected in the
embedded widget on their own page without touching code; and an operator can work a shift in the
console — from the login page onward — without the interface being the hard part — verified live, by actually working conversations
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
- Retention as a real mechanism (`13-06`, `adr/0031`): `messages` partitioned by an immutable
  retention class then by month, so a per-tier history window costs one `DROP PARTITION` rather than
  bounded-batch deletes; expired periods archived to object storage in `16-03`'s export format and
  retrievable as a file, rather than deleted outright.
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
- The first concrete channel adapter, needing no legal or reliability spike: MAX, chosen deliberately
  as the first one built (an open Bot API, no known regulatory friction, `14-02`, done). **SMS
  (`14-03`) will not be built** — a business decision, not a technical one
  (`ago-business/decisions/0008`, 2026-08-29): deprioritized entirely in favour of WhatsApp.
- Offline auto-reply: a tenant-toggleable, off-by-default scripted keyword reply for when no operator is
  available, on any connected channel including the widget itself (`14-04`).
- Telegram and WhatsApp explicitly gated behind their own spike/legal-review prerequisites, not built
  speculatively ahead of either (`14-05`). Telegram's own prerequisite is now answered — a measured
  ~53% direct-connection failure rate, fixed by routing outbound calls through a relay (`adr/0070`) —
  and its adapter is done, live-verified both directions against a real bot (`14-07`). WhatsApp's legal
  review is the one still open, and now the higher business priority of the two remaining channels
  (`ago-business/decisions/0008`/`0009`).
- VK (`14-08`, done 2026-08-29) and email (`14-09`, done 2026-08-31) join this stage's deliverables,
  cut from `ago-business/decisions/0009`'s honest gap analysis against this product's nearest direct
  competitor - VK named as the qualitatively more important of the two for the actual target customer,
  email as plain table-stakes. VK's own live verification against a real community remains open — see
  the item's own file. Email's own sixth-channel shape is the odd one out among all six: no
  `ChannelCredential` row, no console connect/disconnect endpoint at all (`adr/0080`) - `10-05`'s
  self-hosted relay is deployment-wide, not a per-shop account.
- **WhatsApp (`14-10`) and Avito (`14-11`) join this stage's deliverables, both done 2026-08-30**, cut
  from `ago-business/decisions/0010` - WhatsApp built without waiting on `14-05`'s own unfinished legal
  review (the risk is accepted explicitly, not resolved), Avito built without the quantitative demand
  check `0009` had asked for and never got. Neither has a live-verification pass against a real
  account — the same honest gap `14-08`'s own file names for VK — see each item's own file.
- **Verified channel-identity linking (`14-12`, done 2026-08-30)**, cut from `adr/0079`: closes
  `adr/0055`'s own deferred "future, deliberate, verified linking step" - an operator or a visitor
  themselves can link a second channel identity to the same `Visitor`, verified by the visitor sending
  a real code from the new channel, never inferred. Its own named follow-ups, both done 2026-08-30:
  `14-13` (preferred reply channel - an operator's override for which of a visitor's several linked
  identities a reply goes to, read-time tolerant of a since-unlinked preference) and `14-14`
  (unverified contact details - a phone/email an operator types because a visitor said it, for a
  channel with no adapter at all, deliberately never used for delivery).
- **Phone verification via a proactive call or SMS code (`14-15`, built 2026-08-31, `ago-chat#143`)**,
  from a real prospective-customer conversation: `14-12`'s verification needs a channel that can message
  this system first, which a bare phone number cannot - this item proactively calls or texts a code
  instead, and on confirmation produces the identical `ChannelIdentity` `14-12` already built, rather
  than a parallel trust concept. SMS chosen as the default delivery method; the vendor/gateway itself is
  left undecided, same live-account gap `14-08`/`14-10`/`14-11` already carry. First real consumer is
  `20-09` (Stage 20).
- **Only one process may poll a channel (`14-16`, found and built 2026-09-02, `adr/0089`)** — found in
  the demo stand's own logs while deploying `15-09`: a Worker rolling update made the old and new pods
  poll the same Telegram bot at once, and Telegram answered `409`. That symptom self-healed and cost
  only latency, so it was the smaller half. The half worth an item was that
  `TelegramLongPollingService` and `MaxLongPollingService` were unstated single-instance services
  inside a host `concurrency.md` explicitly documented as running multiple competing replicas —
  `replicas: 1` hid the contradiction rather than preventing it. **The fix inverted the item**: poll
  ownership is claimed *per `ChannelCredentialId`* by a session-scoped Postgres advisory lock, so
  replicas share the bot fleet instead of one process monopolising it. It ships as a capability, not a
  restriction, and the `409` is verified gone on the live stand rather than merely explained.

**Done when:** a real message sent via MAX reaches an operator through the same console queue a widget
conversation already does, and a visitor gets an automatic reply when no operator is online, on at
least one connected channel - already true today (`14-02`/`14-04`, both done); VK/email/WhatsApp/Avito
each extend the same bar to a new channel as they land, not raise it.

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
- The four static frontends joined the registry too (`15-07`, done) — every running pod now says which
  commit it is, not only the three `Ago.Chat.*` hosts. **What that item left standing, found live
  2026-08-30**: none of the four sets `Cache-Control` at all, so identity and freshness turned out to
  be two different questions - a deployed, verified fix can still be invisible to an already-cached
  visitor for an unknown length of time (`15-08`, done 2026-08-31, verified live).
- **`messages` repartitioned by tenant hash** (`15-09`, done 2026-09-02, `ago-chat#147`, `adr/0087`) —
  from `LIST (retention_class)` → `RANGE (created_at)` monthly to `HASH (site_id)`, 64 fixed buckets,
  no time dimension. The old key was chosen for retention-by-`DROP` (`adr/0031`) and never for reads:
  checking the real code found `GetHistoryAsync` — the most frequent query in the product — filtering
  `conversation_id` alone, so it pruned *nothing* and visited every leaf partition on every conversation
  open. Both dominant reads now prune to exactly one partition (18 → 1, proven by `EXPLAIN` with a
  negative control, not asserted). The price, taken deliberately: retention loses `DROP PARTITION` and
  becomes a bounded `DELETE` sweep, with `adr/0031`'s archive-before-removal policy unchanged. Removes
  a monthly-recurring CI failure class structurally rather than patching it, and makes buckets a usable
  shard key. Partition count is now constant against both tenant growth *and* elapsed time.
- **Audit every hosted service for multi-replica safety (`15-10`, raised 2026-09-02, not yet built)** —
  `14-16`'s own open question, kept rather than closed. That item found two of the Worker's hosted
  services silently single-instance inside a host `concurrency.md` documented as multi-replica; the
  reason nobody had noticed is that nobody had looked, and nobody has looked at the other thirty.
  `Ago.Chat.Worker` registers 32, of which `adr/0089` settled two. The timer-driven jobs are the group
  that needs thinking about — a periodic job on N replicas fires N times, and whether that is harmless,
  wasteful or wrong is a per-job question. Delivers an audit and a verdict table in `concurrency.md`,
  including for the ones that are fine; fixes anything unsafe as its own item, not smuggled in. Blocks
  any decision to scale the Worker, without making that decision — which still needs a number (rule 7).
- Two open defects re-homed here rather than left belonging to no stage: `5-13` (a presigned upload's
  size ceiling is never enforced by storage — the one path by which a stranger can write unbounded
  bytes to a shared 2Gi volume) and ~~`6-09`~~ (operator capacity is released only on disconnect, so a
  live operator's usable capacity decays until their connection drops) — `6-09` shipped 2026-08-25;
  the demo deployment picks up its repair migration on the next redeploy, which is what unjams its
  waiting queue.

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

- `17-03` — a secret inventory and a rotation procedure per secret. Handling is already sound;
  rotation does not exist, and the visitor signing key turns out to be a customer-visible incident to
  rotate rather than routine maintenance.
- `17-04` — dependency and image scanning. There is none: no Dependabot in any of the seven
  repositories, no vulnerability check in any of the four CI workflows, and two repositories with no
  CI at all, one of which builds a container image.
- ~~`17-05`~~ — **done 2026-08-26.** Runtime hardening. Every workload now carries an explicit
  `securityContext` and five `NetworkPolicy` resources are enforced, each proven live rather than
  applied — a static-file pod that could open a Postgres connection and write into its own served
  docroot can now do neither. Three things the item did not expect: MinIO was the one image genuinely
  running as root and needed a root init container to stop; `fsGroup` is the field that *breaks*
  Postgres rather than helping it; and the `preStop` hook on all three `Ago.Chat.*` hosts had never
  once run, because a chiseled image has no shell (`adr/0054`, and `edge.md`'s correction). The four
  nginx images still run root by statement, with the exact per-repository fix written down.
- ~~`17-06`~~ — **done 2026-08-25.** Authentication and tokens. The realm now sets brute-force
  protection, a password policy and TOTP parameters, and every Keycloak lifetime; the visitor token's
  thirty days is a stated decision rather than an unexamined number (**seven since `17-08`** — see
  below; the decision moved, which is the point of having stated it); per-token revocation and a
  registration CAPTCHA are both answered "no" with the trigger that reopens each (`adr/0034`). Two
  things the item did not expect. The two token schemes really cannot be substituted for one another —
  now tested, both directions — but the shared attachment route had a *third* principal it silently
  classified as a visitor (a Keycloak identity with no `operators` row, creatable by anyone since
  `10-01`); nothing was reachable through it and it is closed at the policy layer. And the visitor
  token's lifetime turned out not to be a free knob: the widget has no renewal path, so shortening it
  breaks returning visitors sooner without buying anything — hence `17-07`.
- ~~`17-07`~~ — **done 2026-08-26.** Silent renewal for visitor sessions, the widget half. Created by
  `17-06`. Deliberately shipped inert: it renews at the point of use, reads its own window out of the
  token rather than hard-coding one, and treats a `404` as transient — so it was correct against the
  API as deployed, and did nothing until its other half landed. `adr/0048` specified the contract for
  both halves instead of leaving the second one to guess.
- ~~`17-08`~~ — **done 2026-08-26.** The `Ago.Chat.Api` half: `POST /api/v1/visitor-sessions/renew`,
  authenticated on the Visitor scheme, with `sub` and `site_id` taken from the validated principal and
  never from the body, and a `403` when the public key in the body resolves to a different site than
  the token claims. `VisitorTokenLifetime` is seven days now, which is what finally separated "how
  long one token stays useful" from "how long a returning visitor keeps their history" — the
  conflation `17-06` found and could not fix on its own. `17-03`'s key-rotation drain window inherits
  the new number. Not yet walked end to end through a browser against a running stack; the item says
  what that walk still has to show.

Scoped 2026-08-25, each against a real audit rather than a checklist, and each kept separate from
`17-01` on purpose: none of them is the tenancy boundary, and folding them together would mean
shipping none of them properly. Abuse controls beyond `3-05`'s rate limits turned out not to need
their own item — registration abuse sits in `17-06` next to the brute-force settings it interacts
with, and owner-facing abuse signals across tenants are already `12-02`'s.

**Done when:** no tenant-scoped operation lets a caller from another tenant reach anything, and that
is enforced by something that fails automatically rather than by remembering (`17-01`); no live bearer
token is written anywhere that keeps it (`5-14`, `17-02`); every secret has a rotation procedure that
states what it breaks, and rotating the visitor signing key is no longer a mass logout (`17-03`); a
newly published vulnerability in a shipped dependency or base image reaches a person without anyone
going to look (`17-04`); no container runs as root or can reach a database it has no business
reaching, by statement rather than by inheritance (`17-05`); and the realm's password, brute-force and
token-lifetime settings are values somebody chose rather than defaults nobody saw (`17-06` — **done**,
`adr/0034`).

Note what this stage does *not* claim when it is done: that the system is secure. It claims that the
six properties above (`17-01`..`17-06` — `17-07` is follow-up work `17-06` produced, not a seventh
property) are enforced by something other than memory, and that the facts behind them were
established rather than assumed — which is the only kind of security claim this project is in a
position to make honestly.

---

## Stage 18 — Operator productivity

**Goal:** the console stops being a place where an operator can only do the obvious thing slowly.
Scoped 2026-08-25 from the list `11-06` deliberately refused to grow into — canned responses, search,
transfer, notes and tags, shortcuts and notifications — which had been named and left unsliced ever
since.

Placed after Calendar and Inbox on purpose. None of it is broken, none of it blocks anything, and a
support product with no customers gains less from a faster console than from a second product proving
the platform claim. It is here so the queue does not run dry, and because two of its original five items
are genuinely interesting rather than filler.

`18-06`/`18-07` joined the stage 2026-08-28, found live rather than planned from `11-06`'s original list
— an operator's queue accumulating conversations nobody ever closes is the same "console does the
obvious thing slowly" problem the rest of this stage names, just discovered by testing `14-02` rather
than by the original scoping pass.

Deliverables:
- `18-01` — search across conversations. **The hard one**, and not for the obvious reason: `messages`
  is partitioned by month and, after `adr/0031`, by retention class too, so a full-text index over it
  is one index per leaf partition and a search touches all of them unless the query prunes — and
  pruning needs a time bound the operator has not given. The item therefore decides what a search may
  *cost*, and requires the bound to be visible rather than a silent truncation.
- `18-02` — transfer a conversation to a named operator. **The second hard one**: a contended change to
  exactly the state `4-02` exists to protect, two compare-and-sets that must agree, and `adr/0037`'s
  lock order to respect or reproduce `6-10`'s deadlock. `6-09` and `6-10` are the evidence this area
  punishes carelessness.
- `18-03` — canned responses, reusing `14-04`'s per-site scripted replies rather than inventing a
  second store of canned text.
- `18-04` — internal notes and tags. Its one correctness property: a note is invisible to the visitor,
  and the visitor-facing read path must be *incapable* of returning one rather than merely filtering
  it — which is also the argument for where a note is stored.
- `18-05` — shortcuts and notifications, extending `11-06`'s attention model, both defaults off.
- `18-06` — auto-close conversations nobody has touched in a while, freeing the capacity they still hold
  and clearing them from "Assigned to me" without an operator ever pressing a button. State change only
  — nothing is deleted, and `15-04`/`16-02` still own retention and erasure unchanged.
- `18-07` — a returning channel visitor's past conversations, visible to the operator handling their
  current one. What makes `18-06` safe rather than lossy actually worth something to a human.
- `18-08` — basic operator/site analytics (done 2026-08-29), cut from
  `ago-business/decisions/0009`'s gap analysis: conversation volume, first-response time and missed
  count, per channel - "how am I doing" visibility this product has never had, distinct from `12-02`'s
  cross-tenant platform-owner view.
- `18-09` — the same numbers, per operator (`18-08`'s own named follow-up, **done 2026-08-30**). `18-10`
  (**done 2026-08-30**) — an operator-reported conversion outcome and the report built on it, the only
  shape that closes `0009`'s "sales funnel" gap without reopening the CRM-depth question `0009` already
  rejected. `18-11` (**done 2026-08-30**) — a topic/tag breakdown on top of `18-04`'s tagging, now built
  at real coverage since `19-02` landed the same day. All three cut 2026-08-30, from
  `ago-business/decisions/0009`/`0010`.
- **A second reporting round, cut 2026-08-30** after the author's own direct follow-up that per-operator
  numbers alone were not the reporting depth asked for: `18-12` (**done 2026-08-30**) — a visitor
  traffic-source report (referrer/UTM), the "источники диалогов" half of `0009`'s own gap that no
  existing report touches at all, since channel (`18-08`) answers a different question than traffic
  source. `18-13` (**done 2026-08-30**) — average conversation duration, the cheapest item either round
  has cut (the timestamps already exist). `18-14`
  (**done 2026-08-30**) — a chat-to-booking conversion report, the literal "did this convert into a
  booking" ask, built as an
  honest proxy (a `calendar` module task started/closed) rather than a confirmed-booking claim
  `ModuleTaskState`'s own two-value ceiling cannot honestly support — see the item's own file for why,
  and its own named relationship to `20-08` (since done, 2026-09-02).

Interface i18n stays out of scope (`vision.md`), and is the one entry on `11-06`'s original list that
did not become work here.

**Done when:** an operator can find an old conversation, hand one to a colleague without losing the
capacity accounting, answer a repeated question without retyping it, leave a note the visitor can never
see, be told a conversation arrived without watching the tab, and never see their queue fill up with
conversations nobody is coming back to.

---

## Stage 19 — AI assistance

**Goal:** the largest and riskiest gap `ago-business/decisions/0009` named against this project's
nearest direct competitor, planned
2026-08-30 (`ago-business/decisions/0010` moves it from "not yet, no real demand signal" to "scope it
now" by direct author decision). `docs/adr/0078` splits "AI automation" into five distinct
capabilities with five different risk profiles rather than treating it as one feature - this stage
builds the three lowest-risk ones; the other two (product/inventory Q&A, AI-triggered booking) are
named in that ADR with their real prerequisites, not cut as items here. Chat-side work through and
through, so it takes the number Stage 10 left reserved rather than a new one after Stage 21.

Deliverables:
- `19-01` (**done 2026-08-30**) — an AI-drafted reply suggestion into an operator's composer, editable
  and discardable, never sent without the operator choosing to. No architecture change, no
  customer-facing hallucination risk - the visitor never sees anything the operator did not read first.
  Live verification against a real YandexGPT account remains open — no such account exists in this
  environment.
- `19-02` (**done 2026-08-30**) — automatic conversation categorization into a site's own existing tags
  (never inventing new ones), closing the real dependency `18-11`'s own file names. Not verified against
  a real YandexGPT account — no such account exists in this environment.
- `19-03` (**done 2026-08-31**) — an AI FAQ module, the second real consumer of `20-07`'s module
  contract after Calendar - `adr/0065`'s own bet that the closed-primitive-vocabulary design would
  generalize beyond one module, confirmed: both guard tests pass unmodified. A real conversation
  through the widget, and a real OpenAI-compatible provider, remain unverified — no such deployment or
  API key exists in this environment.

**Done when:** an operator can request and use an AI-drafted reply, a real site's conversations get
tagged automatically from its own vocabulary without operator effort, and a visitor's routine question
gets answered by a module `Ago.Chat.*` has no special knowledge of - the third one proven, not
assumed, by the identical guard 1/guard 2 tests `20-07` already built passing unmodified against a
second module.

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
- **Calendar becomes a chat module** (`20-07`, done 2026-08-29) — a visitor books inside a
  conversation, on any channel, with `Ago.Chat.*` carrying no knowledge that appointments exist
  (`adr/0065`, `adr/0077`). Live end-to-end verification (a real click-through booking, and the same
  flow over a real text channel) is the one piece still open - see the item's own file.
- **Chat-originated booking requires a verified phone (`20-09`, done 2026-08-31)**, from a real
  prospective-customer conversation and a real launch prerequisite for that customer, not a
  hypothetical: `14-15` verifies before the real claim (`IBookingStore.TryBookAsync`) is ever reached,
  deliberately leaving `20-04`'s own confirm-by-default sweep untouched. First real consumer of `14-15`
  (Stage 14). Scoped to chat-only, not universal - the public widget's own path to the same guarantee is
  `20-10` (done 2026-09-01, then reversed - see below), and the deferred additional-channels want is
  `20-11` (done 2026-09-01, `ago-chat#145`) - a priority-ordered list of extra verified contact channels
  per booking, scoped to the chat conversation's own module task, both new the same day as `20-09`.
- **Permissioned contact visibility, a tenant contacts report (`20-12`, done 2026-08-31)** - a cheaper,
  faster interim step named ahead of `20-10`'s own full verification: an operator holding
  `Permission.CustomerRead` sees a pending booking's phone and can eyeball/reject an obviously fake one
  within the confirmation window; one without the permission does not. The account owner (the first
  operator a tenant's own provisioning creates) is guaranteed by the aggregate itself, not a console
  convention, to always hold a role granting that permission (`adr/0083`).
- **The tenant's own scheduling tools** (`20-13`..`20-18`, scoped 2026-09-01) — the console side of
  Stage 20, which `20-06` left as an add-only form: a worker card and list with real name fields,
  activity and deletion (`20-13`, done 2026-09-01, `ago-calendar#14`/`ago-calendar-console#15`); a
  schedule template that can express a **cycle** - "2 через 2",
  "сутки через трое" - rather than only an ordinary week, with slot length, buffer and horizon moved to
  where a tenant sets them (`20-14`, done 2026-09-01, `ago-calendar#16`/`ago-calendar-console#17`,
  `adr/0084`); a plain table of what the materialiser actually
  produced, reusing `20-12`'s contact gate rather than working around it (`20-15`, done 2026-09-01,
  `ago-calendar#15`/`ago-calendar-console#16`); and re-cutting an
  already-materialised horizon (`20-16`, done 2026-09-01, `ago-calendar#17`/`ago-calendar-console#18`,
  `adr/0085`) - which leaves the background job insert-only as `adr/0053` promised and makes
  destruction one explicit human action with a preview. Two follow-ons fall out of it: **a booking may
  span several consecutive slots** (`20-18`, done 2026-09-01, `ago-calendar#18`/`ago-calendar-console#19`,
  `adr/0086` amending `adr/0059`) - the claim generalises from a single-row compare-and-set to a
  claimed-set one, still one statement, still Postgres as the sole arbiter, still atomic: a booking is
  claimed whole or not at all; and moving a booking into the new grid instead of cancelling it
  (`20-17`), deferred by the author and not queued.
- **The public widget's own verified-phone mechanism, built then closed, same day (`20-10`, done
  2026-09-01, `ago-calendar#19`)** - `20-09`'s own named follow-up for the one calling surface it
  deliberately left untouched. A second, independent `PendingPhoneVerification` aggregate mirroring
  `14-15`'s confirm-side domain logic (code hash, expiry, lockout, constant-time compare), with no
  cross-product dependency (`adr/0027`). `FakePhoneVerificationSender` is the only sender registered,
  unconditionally - the code is real, generated, hashed, checked for real; only the SMS/voice call is
  faked, which is what makes the whole flow live-demonstrable with zero vendor spend, a bar `14-15`
  itself never cleared. **Found the same day it shipped**: `20-07` had already deleted `ago-widget`'s
  entire direct HTTP client to Calendar five days earlier, so no caller reaches this endpoint at all -
  every booking now runs through the chat conversation instead. The endpoint and its verification
  primitive stay in the codebase, closed rather than deleted (`PublicBookingApiGate`, `ago-calendar#20`,
  off by default, no exception for any caller including AGO's own platform-owner role), reversible with
  one config flip if a real third-party-integration need is ever named. `20-19`, proposed on the premise
  that such a caller was a tenant's own integration, was reconsidered and withdrawn the same day - see
  `20-10`'s own file for the full trail.
- **A chat operator can act on a booking that started in a conversation** (`20-08`, done 2026-09-02,
  `ago-calendar#21`/`ago-calendar-console#20`, `adr/0088`) - the tension Stage 20 carried from the day
  `20-07` shipped: `adr/0065` promises the operator may always intervene, `adr/0027` forbids the two
  products sharing an `Operator` row. Resolved by **applying `adr/0027` a second time rather than
  amending it**: the tenant invites a colleague by name and email from the Access screen `20-12` already
  built, creating a real Calendar `Operator` with no subject yet; the first authenticated request from
  that person matches their email claim against invited rows and links. Linking happens on
  authentication, **never on acting** - an action from an unknown subject is refused, not
  auto-provisioned, which is the failure mode `12-04` caught once already in a different disguise. A
  narrow per-action capability was chosen first and reversed on the author's own challenge, because it
  needed *more* new machinery than the shape it was supposed to be cheaper than. First authorization
  question in this project to span two products, so `authorization.md` gained a section of its own.

- **The booking workflow the first tenant actually uses (`20-21`, `20-22`, `20-23`, cut 2026-09-02 from
  `adr/0090`)** — all three blocked on `20-20`, because none is verifiable by hand until Calendar runs.
  `20-21`: an operator creates a customer and a booking, finds an existing customer by a phone typed in
  any of its equivalent forms, and corrects a mistyped number (which clears its verification). This is
  the tenant's primary intake — telephone and walk-in — and it has no implementation at all today.
  `20-22`: moving a booking as a chain, preserving `adr/0086`'s anchor identity, delivering the
  mechanism `20-17` was deferred waiting for. `20-23`: attendance, revenue as **accounting** rather
  than a note, and — urgent independently of any policy — recording *when* and *at whose initiative* a
  cancellation happened, which today survives only in a domain event and is unrecoverable afterwards.
  `NoShowCount` has had no writer since it shipped and gets one here.

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
