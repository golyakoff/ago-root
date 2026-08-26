# ADR-0057: How long logs, traces and metrics are kept, and what actually enforces it

- **Status**: Accepted
- **Date**: 2026-08-26
- **Stage**: 16

## Context

`16-01` inventoried where personal data lives and left three rows it could not answer from the code:
what trace spans actually carry, what the node's log rotation actually does, and whether Prometheus's
labels are person-shaped. `16-05` answered all three by running the system and reading the output
rather than the configuration. Two of the answers were about *content* and are recorded in
`architecture/personal-data.md`; this ADR is about the third question, which the audit turned out to
matter more than expected: **how long any of it is kept.**

What was measured on the local cluster on 2026-08-26 — all of it, not one example:

- **Container logs had no retention of any kind.** On the Docker Desktop node the worker's log was a
  single unrotated **87.9 MB** file after 2.5 days, with **229 MB** of container logs on the node in
  total. The k3s demo node is better only by inheritance: kubelet rotates at its own defaults (10 MiB
  per file, 5 files), which bounds volume and says nothing about age. Neither number was chosen by
  anybody, and `personal-data.md` said only "whatever the node's log rotation does — not defined by
  anything in this project", which was accurate and useless.
- **The volume was almost entirely framework noise.** Of `Ago.Chat.Webhooks`' 571,766 captured log
  lines, 130,483 log entries were ASP.NET Core's "Request starting/finished" pair, 97,864 were
  "Executing endpoint", and 19,177 were EF Core's full SQL statement text. `Ago.Chat.Worker` was the
  same shape. Only the API set `Microsoft.AspNetCore: Warning`; none of the three turned down EF's
  command logging. This matters to retention directly: a size-bounded rotation window buys a length
  of *time* that is inversely proportional to how much is written into it.
- **Jaeger had been OOMKilled seven times.** `jaegertracing/all-in-one`'s in-memory store defaults to
  unlimited, so it grows until the container hits its memory limit and the kernel kills it. The
  documented answer "traces live until the pod restarts" was true by accident: the pod restarts
  *because* of the traces. That is retention by crash — it loses every trace at once and takes the
  trace backend down with it.
- **Prometheus was on its own default** (15 days, no size limit) with a 1Gi PVC, and one label —
  `node`, whose value is the API pod's `HOSTNAME` — grows one new series per pod replacement. Eight
  distinct values existed on a single-node local cluster, plus the `deliver-to-connections.<node>`
  topic label derived from it.

Two facts frame the decision. `17-02` removed the query string from the edge access log, so what
those lines still carry is the **client IP** — personal data, and the specific thing `16-05` was
opened to bound. And `adr/0050` set the backup window to 30 days, labelling it a choice rather than a
derivation because no published privacy policy exists yet to align it to; the same honesty applies
here.

## Decision

### 1. Container logs — including the edge access log — are kept for 14 days

The number is a choice, not a derivation. Two considerations set it:

- An investigation opened by `15-03`'s alerting has to be able to look back across **two weekends**.
  A one-week window means an alert that fires on a Friday and is investigated properly the following
  week has already lost the days before it.
- A log of client IPs **earns less every day it is kept while costing the same**. Unlike a backup,
  whose value is constant until it is needed, a request log's usefulness decays fast.

It is deliberately **not** the backup window's 30 days. Those two numbers answer different questions —
a restore must be possible; an investigation must be possible — and the shorter one is right for the
store that is more sensitive per byte and less useful per day. When a privacy policy is written, this
number and `adr/0050`'s are two separate statements, and each lives in exactly one variable so that
aligning either is one edit.

**Enforced by two mechanisms, because neither is sufficient alone.**

| Mechanism | Bounds | Where |
|---|---|---|
| `CronJob/log-retention`, daily | **Age**: deletes kubelet's rotated container-log files (`N.log.<timestamp>`, `.gz`) older than `RETENTION_DAYS` | `ago-deploy/k8s/base/log-retention.yaml` |
| kubelet `containerLogMaxSize` / `containerLogMaxFiles` | **Size** of the file a live container is still writing to | `/etc/rancher/k3s/config.yaml` on the node; `runbooks/public-deploy.md` |

The split follows from what is safe to touch. A container's *current* log file is held open by the
runtime; unlinking or truncating it under a live writer is how a cleanup job becomes an outage. So the
job only removes what kubelet has already finished with, and bounding the live file is the node's job
and is necessarily a size limit rather than an age limit. **Stated plainly: a very quiet container's
current log can hold lines older than 14 days, because nothing rotates it until it grows.** That is
the honest limit of this decision, and it is bounded rather than open-ended — the file cannot exceed
the size limit, and rotation moves it into this job's reach.

A CronJob rather than a `logrotate` entry on the node (which `adr/0040` uses for Postfix's mbox):
these files belong to kubelet, and a second rotator racing kubelet for the same paths is worse than no
rotator.

**14 is the target; the ceiling is 16.** `find -mtime +14` deletes at strictly more than 14 whole
days, and a daily schedule can add another day before the job next runs. A privacy policy states a
ceiling, so the honest number to publish is **16 days**, and pretending otherwise by tuning `-mtime`
down would trade a documented overshoot for an undocumented undershoot.

### 2. Traces are bounded by count, not by time: 10000

`jaegertracing/all-in-one`'s memory store offers no TTL, only `MEMORY_MAX_TRACES`, so the honest
statement is a count and not a duration. The number is derived from a measurement rather than picked:
3000 requests driven through the API moved the Jaeger pod's `process_resident_memory_bytes` from
54.7 MB to 70.8 MB — **~5.4 KB of resident memory per trace** at the shape this deployment produces.
Sized against a pessimistic ~20 KB for a fatter real conversation trace, 10000 traces is ~200 MB
inside the pod's 512Mi limit, which leaves the Go runtime room to collect rather than be killed.

**What this buys in time is currently about an hour**, because the overwhelming majority of spans are
liveness/readiness probes and Prometheus scrapes. That is a fact about what is traced, not about the
limit, and the fix is to filter health-probe routes out of the ASP.NET Core instrumentation — named as
a follow-up in `backlog/16-05`, deliberately not solved by choosing a bigger number here.

### 3. Metrics are kept 14 days, and also capped at 768MB

Time aligned with the container-log window, for the same reason and so that one date bounds "what can
still be looked at". Prometheus's own default is 15 days, so the behavioural change is one day; the
change that matters is that the number is chosen and written down.

The size cap exists because time-based retention alone does not stop a cardinality growth from filling
the 1Gi volume before the fourteen days are up, and the audit found exactly that growth in the `node`
label. Whichever limit binds first wins.

### 4. Less is written, so that the windows above mean more

`Microsoft.AspNetCore` goes to `Warning` on all three hosts (it already was on the API — `17-02` found
the divergence and handed it over) and `Microsoft.EntityFrameworkCore.Database.Command` goes to
`Warning` on all three. Measured effect on the worker: **10,469 of 238,656 log entries survive** —
95.6% of entries removed, and a larger share of lines, since the removed ones are multi-line.

EF's statement text carries no personal data today, because parameters are logged as `?` while nothing
calls `EnableSensitiveDataLogging`. It is turned down anyway for the retention reason above and
because a full statement log is one flag away from being a full parameter log, which for this schema
means `messages.body` on every insert. `Warning` rather than `None`: EF logs real problems in the same
category.

## Consequences

**Positive.**

- The question "how long is a client IP kept" has a number, and something that runs enforces it. It
  was demonstrated expiring a real file in the Gateway's own log directory before this was written,
  not asserted from the manifest.
- Jaeger stops being OOMKilled, which is an availability fix found by a privacy audit.
- Prometheus cannot fill its volume, whatever the label cardinality does.
- Container-log volume drops by roughly two orders of magnitude, which makes the node's size-based
  rotation cover far more days than it did.

**Negative, and named rather than glossed.**

- **The pruner is the only workload in this cluster that runs as uid 0 with a writable hostPath.**
  Deleting root-owned files under `/var/log/pods` needs it — node-exporter gets away with `nobody`
  only because everything it needs is read-only. All capabilities are dropped and the mount is one
  directory rather than the host root, but this is a real widening of `17-05`'s hardening and is the
  cost of the decision.
- **Turning EF's command log down costs debuggability.** "Which statement ran, with what shape" is
  gone from production logs; the trace's `db.query.text` still carries it, which is where that
  question belongs (`coding-style.md`: log identifiers, correlate through the trace id).
- **Trace retention is now explicitly short.** An hour of history is worse than the "until the pod
  falls over" it replaces *for a lucky reader*, and much better for an unlucky one. The follow-up that
  makes it genuinely useful is filtering probe traffic.
- Two retention numbers exist (14 days here, 30 days in `adr/0050`) and a privacy policy will have to
  state both.

## Alternatives considered

**Set kubelet's rotation parameters and call that the retention policy.** Rejected as insufficient
rather than wrong — it is half of decision 1. Kubelet's limits are size-based, so they cannot express
"14 days" at all, and the answer to "how long do you keep client IPs" cannot be "it depends how busy
we were".

**Turn the access log off, or drop `$remote_addr` from its format.** This would remove the personal
data instead of bounding it, and it was tempting: the per-IP rate limit is enforced by nginx itself
and reads nothing from the log. Rejected because a request log on a public deployment with no way to
tell one client from another is close to useless for the one job it has left, and because "delete the
evidence" is not the same answer as "keep it for a defined period" — the second is what a privacy
policy can actually state.

**A `logrotate` entry on the node, following `adr/0040`'s precedent for Postfix.** Rejected: those
mbox files have no other manager, whereas `/var/log/pods` is kubelet's, and two rotators on one set of
paths is a race.

**Prune inside the pruner more aggressively — remove empty pod log directories too.** Written, tried
on a live cluster, and withdrawn. A pod's log directory is briefly empty between kubelet creating it
and the container's log symlink appearing, so an "obviously safe" `-type d -empty` prune deleted the
log directory of a pod that was still starting, including on one run the pruner's own. It was also
unnecessary: kubelet garbage-collects orphaned pod log directories itself, and an empty directory
holds no bytes and therefore no personal data.

**Raise Jaeger's memory limit instead of bounding the trace count.** Rejected: it moves the OOM rather
than removing it, on a single small VPS where `15-05` is already asking where the headroom is, and it
still leaves "how long is a trace kept" unanswerable.

**Align every window on 30 days for one simple policy sentence.** Rejected — see decision 1. A single
number would be easier to publish and would keep client IPs twice as long as anything needs them.
