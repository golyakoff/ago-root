# Personal data outside the database: logs, traces, and what an incident would need

- **Stage**: 16
- **Status**: done — **2026-08-26.** Logs, traces and metrics were read off a running cluster rather
  than off the code. **Nothing sensitive was found in any of the three.** What was found instead: no
  retention anywhere (the local node was keeping container logs *forever*, in one unrotated 88 MB
  file), Jaeger being OOMKilled by its own unbounded trace store, over 99% of the log volume coming
  from framework loggers nobody had configured, and two span attributes carrying values nobody in this
  project wrote. All four are fixed or bounded; the retention numbers are in `adr/0057` and are
  enforced by mechanisms that were demonstrated running.
- **Depends on**: `16-01-personal-data-map-and-residency-constraint.md` — this item fills in the rows
  that map marked "unverified". All of them are now closed; the new residuals are listed at the bottom
  of this file and in `personal-data.md`.

## Goal

The two stores nobody has actually looked inside — traces and logs — are known rather than assumed,
and the edge access logs that hold client IP addresses have a defined retention instead of an
unbounded one. After this, `personal-data.md`'s table has no "unverified" row left, and a question
like "what data was affected" has an answer that does not start with a guess.

## What was found (2026-08-26, local Docker Desktop cluster, `runbooks/k8s-local.md`)

Method note first, because it decides how much the results are worth: every number below was read off
a cluster that had been running for 2.5 days with real traffic through the Gateway, not derived from a
manifest. Where something is a reading of configuration rather than a measurement, it says so.

### 1. Application logs — clean of personal data, and 99% noise

1,189,729 log lines captured from the three hosts (`Ago.Chat.Api` 1,253; `Ago.Chat.Worker` 616,710;
`Ago.Chat.Webhooks` 571,766) and searched.

**Not found, having been searched for specifically**: any email-shaped string (0 matches in all
three), any JWT-shaped string (0), any client IP. The only IP addresses present anywhere are the pods'
own (`10.1.0.61`, `10.1.0.64`), printed by ASP.NET Core's request logging as part of the host's own
URL. So `16-01`'s claim about hand-written logging holds.

**But `16-01`'s method would not have caught a leak, and that is the finding.** Its evidence was "a
grep over every `Log*(` call in `ago-chat/src`" — a statement about *this project's* code. Broken down
by logger category, what is actually on disk is almost entirely framework:

| Host | Category | Log entries in 2.5 days |
|---|---|---|
| Worker | `Microsoft.AspNetCore.Hosting.Diagnostics` | 130,516 |
| Worker | `Microsoft.AspNetCore.Routing.EndpointMiddleware` | 97,888 |
| Worker | `Ago.Chat.Worker.*` (all of it) | 10,465 |
| Worker | `Microsoft.EntityFrameworkCore.Database.Command` | 273 |
| Webhooks | `Microsoft.AspNetCore.Hosting.Diagnostics` | 130,483 |
| Webhooks | `Microsoft.AspNetCore.Routing.EndpointMiddleware` | 97,864 |
| Webhooks | `Microsoft.EntityFrameworkCore.Database.Command` | 19,177 |
| Webhooks | everything this project wrote | **0** |
| API | `Microsoft.EntityFrameworkCore.Database.Command` | 86 |
| API | `Microsoft.AspNetCore.SignalR...DefaultHubDispatcher` (failures) | 55 |

Two things follow. `17-02`'s finding 4 — that Worker and Webhooks never set
`"Microsoft.AspNetCore": "Warning"` and so print the full request URL on every health probe and every
Prometheus scrape — is not merely "log noise"; it is essentially the entire log. And **EF Core logs
the text of every SQL statement it executes at `Information` on all three hosts**, which nobody had
noticed because `Default: Information` was doing it silently.

The SQL text carries no values: parameters print as `@p0='?'` because nothing calls
`EnableSensitiveDataLogging`. That is one flag away from `messages.body` on every insert, which is
what the guard test now covers.

**One near-miss checked and cleared.** SignalR's `Failed to invoke hub method 'SendMessageAsync'` log
prints the *method signature* — `SendMessageAsync(Guid conversationId, String body, ...)` — not the
argument values. A reader skimming for "body" in a log finds the word and not the text. Worth
recording because the two look identical at a glance.

### 2. Container-log retention — there was none, measured rather than assumed

`personal-data.md` said "whatever the node's log rotation does — not defined by anything in this
project". The answer on the local node was **nothing at all**: the worker container's log was a single
**87,985,374-byte** file after 2.5 days, unrotated, and `/var/lib/docker/containers` held **229 MB**.
Docker Desktop's `json-file` driver has no size limit unless one is configured, and nothing configures
one.

k3s (the demo node) is different but not better by design: kubelet rotates at its own defaults
(10 MiB × 5 files), which bounds volume and says nothing about age.

This is the item's actual subject. `17-02` removed the query string from the edge access log, so what
those lines still carry is the client IP — and they were being kept forever.

### 3. Traces — clean, and two attributes nobody in this project wrote

All 28 distinct span-attribute keys across the three services were enumerated from Jaeger's own query
API, with sample values, not sampled by eye.

**Nothing person-shaped.** No body, no email, no token, no client IP. The inbound query string is
`Redacted` by the ASP.NET Core instrumentation, exactly as `17-02` established; `db.npgsql.data_source`
carries the connection string with the **password stripped by Npgsql itself**.

Two attributes are worth naming because no line of code in this repository asks for them:

- **`db.query.text`** — the **full SQL statement**, on all 488 database spans. Parameterised, so no
  values; it is safe only for exactly as long as that stays true.
- **`url.full`** — the whole outbound URL, on every `System.Net.Http` span. This one matters for a
  reason specific to this product: the only outbound HTTP call `Ago.Chat.Webhooks` makes is to a URL
  **the tenant typed**, and a webhook URL with a shared secret in its query string is an ordinary
  thing for a tenant to configure. Checked, and it is redacted — but by the **.NET runtime's own URI
  redaction**, which is a *different* switch from the `OTEL_DOTNET_EXPERIMENTAL_...` one `17-02` named
  for the inbound side. That is now a test rather than a fact somebody has to remember.

**And the thing that was actually broken.** The Jaeger pod had been **OOMKilled 7 times**, the most
recent at `2026-08-26T07:57:02Z`, minutes before it was read. `jaegertracing/all-in-one`'s in-memory
store has no default bound, so it grows until the 512Mi container limit kills it.
`personal-data.md`'s "until the pod restarts, which on this cluster is frequent" was true and had the
causality backwards: the pod restarts *because of* the traces. Retention by crash — it loses
everything at once and takes the trace backend down with it. Found by a privacy audit, fixed as an
availability bug.

### 4. Metrics — nothing person-shaped, one unbounded label

All 47 label names enumerated, and every candidate's values read.

- `network_peer_address` and `server_address` hold **this cluster's own** addresses — they come from
  *outbound* HttpClient instrumentation, not from inbound requests. ASP.NET Core's server metrics
  carry no client address at all.
- `http_route`, `hub`, `topic`, `consumer`, `capacity` are shaped as `7-02` intended.
- **`node` grows without bound.** Its value is the API pod's `HOSTNAME`, so every pod replacement adds
  a new series — 8 distinct values on a single-node local cluster already, plus the
  `deliver-to-connections.<node>` values it produces in `topic`. Not a privacy problem; a cost and
  stability one, and the reason a size cap was set alongside the time window.

So `16-01`'s "labels look site/consumer/topic-shaped, but that was read, not measured" is now measured,
and the reading was right.

### 5. What `17-02` left open, re-checked and unchanged

nginx's **error** log still prints `request: "..."` and the upstream URI with the query string intact,
and still cannot be configured otherwise. A *failing* hub connect therefore still writes a bearer
token to disk. This item does not close it — it bounds it, since those lines are container stdout like
every other and are now covered by the same 14-day window.

## What changed

**`ago-deploy`**

- `k8s/base/log-retention.yaml` (new) — a daily `CronJob` deleting kubelet's rotated container-log
  files older than 14 days. The one workload in this cluster that runs as uid 0 with a writable
  hostPath, argued for in the file and in `adr/0057`; all capabilities dropped, one directory mounted.
- `k8s/base/jaeger.yaml` — `MEMORY_MAX_TRACES=10000`, derived from a measured ~5.4 KB of resident
  memory per trace.
- `k8s/base/prometheus.yaml` — `--storage.tsdb.retention.time=14d`, `--storage.tsdb.retention.size=768MB`,
  with the image's own two default args restored alongside them (naming any arg replaces the whole
  default CMD).

**`ago-chat`**

- All three `appsettings.json`: `Microsoft.AspNetCore` and `Microsoft.EntityFrameworkCore.Database.Command`
  to `Warning`. Measured effect on the worker: 10,469 of 239,146 log entries survive — 95.6% of
  entries gone, and a larger share of lines. On Webhooks, 4 entries survive out of 247,528.
- `tests/Ago.Chat.Integration.Tests/TelemetryLeakGuardTests.cs` (new) — two guards, both against the
  real pipeline rather than against a scrubber in isolation. Detail below.
- `tests/Ago.Chat.Integration.Tests/PostgresFixture.cs` — exposes the container's connection string
  *with* its password, because `NpgsqlDataSource.ConnectionString` strips it.

**`ago-root`** — `adr/0057`, `runbooks/personal-data-incident.md` (new), and the corrections to
`personal-data.md`, `edge.md`, `coding-style.md`, `runbooks/public-deploy.md`.

## The guard, and why it is shaped this way

A convention nobody re-reads is what `17-02` disproved. So the guard runs the production wiring and
reads what came out:

- `AMessageBodyWrittenThroughTheProductionPersistenceWiring_ReachesNoLogAndNoSpanAttribute` writes a
  message whose body is a canary through `AddPostgresPersistence` — the same call every host makes —
  against a logger factory capturing **everything at `Trace`**, which is stricter than any host's
  `appsettings.json` and so cannot pass merely because a level is turned down. The same run is watched
  by an in-memory span exporter subscribed to the same sources `AddPlatformObservability` subscribes
  to. Both halves assert positively first (the body really is in the database; EF really did log) so
  the test cannot pass vacuously. **Inverted before it was kept**: adding `.EnableSensitiveDataLogging()`
  to `AddPostgresPersistence` fails it with the canary printed inside EF's parameter list.
- `AQueryStringOnAnOutboundHttpCall_IsRedactedBeforeItBecomesASpanAttribute` covers finding 3's
  outbound half. **Inverted by moving the canary from the query string into the path**, where nothing
  redacts it — it then fails and prints the whole `url.full`.

That second inversion caught a real defect in the first draft of the test: the canary was being passed
through `Uri.EscapeDataString`, which turns `@` into `%40`, so a search for its literal text could
never have matched whatever the span recorded. The test passed for the wrong reason until the canary
was changed to URL-safe characters. A guard that cannot fail is not a guard, and the only way to know
which kind you have written is to make it fail on purpose.

## Retention: the numbers, and what runs

| Store | Number | Enforced by | Demonstrated? |
|---|---|---|---|
| Container logs, incl. the edge access log | **14 days** target, **16 days** ceiling (`find -mtime +14` is strictly-greater, plus a day of schedule slack — `adr/0057` says which number a policy should quote) | `CronJob/log-retention`, daily | **Yes** — run against the Gateway's real log directory: a rotated file dated 86 days back was deleted, a rotated file dated 1 day back and the current `0.log` both survived |
| Container logs, live file | size, not age | kubelet `containerLogMaxSize`/`Files` | **No** — a node step, written into `runbooks/public-deploy.md` and not applied (see residuals) |
| Traces | **10000 traces**, oldest-first | Jaeger's in-memory ring | **Yes** — with the cap temporarily set to 50, 400 requests were driven through the API and Jaeger retained exactly 50 traces |
| Metrics | **14 days / 768MB** | Prometheus TSDB retention | **Partly** — the running process reports `retention.time=2w`, `retention.size=768MiB` and the matching `prometheus_tsdb_retention_limit_*` metrics; nothing has expired yet on a 2-day-old TSDB and 14 days were not waited out |

The reasoning for 14 rather than 7 or 30, and why it deliberately does not match `adr/0050`'s backup
window, is in `adr/0057`.

## The incident half

`runbooks/personal-data-incident.md`. It states the dependency on `15-03` plainly rather than
politely: the five alert rules that exist watch availability and capacity, **nothing alerts on a
confidentiality event**, so the realistic detection path for a disclosure today is a person, not an
alert — and a quiet inbox is not evidence of health until `15-03`'s external check exists. Scope
determination is a walk down `personal-data.md`'s table with one question per store. Notification is
ordered (author → lawyer → tenant → regulator → individuals) and deliberately carries **no deadlines**;
those, and whether anything is notifiable at all, are the lawyer's via `ago-business`.

One thing the procedure gets from this item specifically: **preserve evidence before restarting
anything**, because traces are in memory and container logs are now pruned on a schedule. The fix made
that instruction necessary, so it is written down where someone mid-incident will find it.

## Done when

- [x] Traces, logs and metrics have been inspected against real traffic, and the findings written down.
      **All three, on a running cluster, with counts.**
- [x] Nothing sensitive is emitted, or what was is fixed, with a guard where one is possible.
      **Nothing sensitive was found. Two guards added anyway, both shown failing first.**
- [x] Edge access-log retention is defined, applied, and recorded. **14 days, `adr/0057`, demonstrated
      deleting a real file from the Gateway's own log directory.**
- [x] `personal-data.md` has no unverified row left. **Three closed; new residuals named below rather
      than left implicit.**
- [x] An incident procedure exists, names its dependency on `15-03`, and says plainly which parts are
      the lawyer's to answer.

## What this leaves open

Named rather than glossed, because the point of the audit was to stop guessing.

- **The demo node's kubelet log rotation has not been applied.** This item was scoped away from the
  live cluster on purpose (another item's unmerged branch was already applied there), so the values in
  `runbooks/public-deploy.md` §3a are written and unexecuted. Until someone runs them the demo node is
  on kubelet's defaults, and a live container's current log file is bounded by 10 MiB × 5 rather than
  by anything chosen.
- **Nothing was verified on the live deployment at all.** Every number here is from the local cluster.
  The manifests are identical (`base/`), the log plumbing is not: Docker Desktop's `json-file` driver
  versus k3s's kubelet rotation.
- **A quiet container's live log can hold lines older than 14 days.** The residual of the fix, not of
  the audit — `adr/0057` states it.
- **Trace retention is now short in wall-clock terms** — 10000 traces is on the order of an hour,
  because almost every span is a health probe or a Prometheus scrape. **The follow-up worth doing is
  filtering probe routes out of the ASP.NET Core instrumentation** (`AspNetCoreTraceInstrumentationOptions.Filter`,
  configurable from each host's `Program.cs` without touching `Ago.Platform.Observability`), which
  would make the same limit buy days instead of an hour. Not done here: it changes what `7-01` chose
  to trace, which is a Stage 7 decision rather than a personal-data one.
- **nginx's error log** — `17-02`'s residual, unchanged, now merely bounded.
- **No log aggregation exists**, so incident scope determination means reading per-pod logs by hand
  within their retention window. Out of scope here and still is.
- **Prometheus's 14-day expiry was not observed happening.** The limits are live in the process; no
  block has aged out yet.
- Two unrelated things the sweep noticed on the local cluster and did not act on: the worker was
  failing every outbox cycle with `column "trace_context" does not exist` and every attachment sweep
  with `relation "attachments" does not exist` — a stale local database against newer images, not a
  defect in either repository.

## Out of scope

- Log aggregation or a log store — there is none, and building one is a separate decision.
- Redacting message content from the database. Content in `messages.body` is the product
  (`personal-data.md`); this item is only about copies of it leaking into places that were never
  meant to hold it.
- Deciding whether a given incident is notifiable, or to whom, or in what timeframe — legal, not this.
- Security hardening generally. This item is about what is recorded, not about who can reach it.
