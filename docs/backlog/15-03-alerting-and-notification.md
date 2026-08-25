# Alerting: rules that fire, and a channel that reaches a person

- **Stage**: 15
- **Status**: done (2026-08-25) — internal alerting only; the external check in "Open questions" below
  is **still open** and is half of what this item's own "Two mechanisms, not one" section asks for
- **Depends on**: nothing new — `7-02-metrics-instrumentation.md` and `7-03-observability-stack-and-
  dashboards.md` already ship every instrument and the Prometheus/Grafana stack these rules read from;
  both explicitly deferred alerting, and this item is where that deferral ends

## Goal

A failure on the public deployment reaches a person without that person happening to open Grafana.
Today the metrics exist, the dashboards exist and are deployed (`deploy/k8s/base/grafana-dashboard-
*.json`), and nothing looks at any of it unless someone is already looking. `7-02` and `7-03` both
declined alerting with the same reason — "a demo cluster, not an on-call rotation" — which was true
when they were written and stopped being true at Stage 8.

## Context to read first

`docs/backlog/7-02-metrics-instrumentation.md`'s "Alerting rules" out-of-scope note and `7-03`'s
"Alerting (Alertmanager)" note — the two deferrals this item closes, and the reason each gave.
`deploy/k8s/base/prometheus.yaml` and `prometheus-scrape-config.yml` — what already scrapes what.
`deploy/k8s/base/grafana-dashboard-*.json` — every panel there is a candidate signal, but a dashboard
panel and an alert-worthy condition are not the same thing, and this item must not simply promote all
of them. `architecture/nfr.md`'s "Availability behaviour" — no SLA, so alert thresholds are about
"something is broken or about to break", not about defending a number nobody promised.
`architecture/realtime.md`'s degradation path — which dependency failing is a real incident and which
is a documented, acceptable degradation, which is exactly the line an alert must not blur.

## Scope

- Alertmanager (or Grafana's own alerting, if that turns out to be less machinery for one node — decide
  and state which, with the reason) deployed as part of the demo overlay.
- A deliberately small first rule set, each rule justified by a failure that has actually happened or
  can plainly happen here, not by a list copied from elsewhere. The candidates, from this system's own
  history and shape:
  - disk usage on the node's local-path volumes approaching full (`15-05`'s subject — and the failure
    mode that takes down every component at once on a single-node deployment);
  - outbox lag growing without bound (`7-02` already instruments it) — the signal that acknowledged
    writes have stopped being published;
  - DLQ count rising — a message is failing repeatedly and nobody knows;
  - a pod in CrashLoopBackOff, or a Deployment with no ready replica;
  - TLS certificate expiry approaching (cert-manager renews automatically; an alert is how you find out
    when it silently did not);
  - the public endpoints being unreachable from outside — see the open question below.
- One notification channel that actually reaches the author, configured from the existing Secret
  mechanism (`overlays/demo/.env`), never committed.
- **Each rule proven by making it fire** — the same "verified means actually run" bar `8-01` and
  `k8s-local.md` already hold. An alert rule that has never fired is a rule that has never been tested.
- A short runbook line per rule: what it means and what to do first. A rule whose response is unknown is
  noise that trains its reader to ignore the next one.

## Out of scope

- An on-call rotation, escalation policy, or paging tool — one person, one deployment.
- Alerting on SLO burn rate — there is no SLO (`nfr.md`), and inventing one to have something to burn
  would be backwards.
- Alerting on the local development cluster. `overlays/local` gets nothing from this item; a developer
  watching their own terminal is the notification channel there.
- Log aggregation and log-based alerts — a different mechanism (there is no log store here at all), a
  separate item if it is ever wanted.

## Done when

- [x] The alerting component is deployed on the demo overlay from a committed manifest.
      `ago-deploy/k8s/overlays/demo/alertmanager.yaml` + `alertmanager-config.yml`, applied to the live
      node and running.
- [x] Every rule in the first set has been made to fire deliberately, and the notification arrived.
      See "How each rule was fired" below — **two of the five were fired by their real condition with
      the rule untouched; three were fired against real series with the threshold relaxed**, because
      the node's disk cannot be filled to 85% and a certificate cannot be aged three weeks on a healthy
      public deployment. The distinction is stated rather than blurred, and `promtool` unit tests cover
      the thresholds those three could not exercise.
- [x] The notification channel's credential comes from the existing Secret mechanism, with only a
      `.example` committed. **Satisfied by there being no credential**: Alertmanager reaches Postfix
      over the same unauthenticated, unencrypted cluster-bridge hop Keycloak already uses
      (`adr/0040`'s amendment). Nothing was added to `.env` or `.env.example`, and the one value that
      genuinely must not be committed — the human mailbox — lives in the node's `/etc/aliases`, which
      is neither a repository nor a Secret.
- [x] Each rule has a one-line "what this means, what to check first" entry in the runbook.
      `ago-root/docs/runbooks/alerting.md`, one section per rule, plus the false positive each rule is
      most likely to produce.
- [x] `7-02` and `7-03`'s out-of-scope notes are updated to point here rather than left contradicting
      the code — `CLAUDE.md`'s "docs are part of the deliverable". Both updated; `7-02`'s also now
      records that `nfr.md`'s "DLQ count" never had an instrument, and how this item answered it
      without adding one.

## What was decided — 2026-08-25

Full reasoning in **`adr/0045`**. In short:

- **Alertmanager, not Grafana's own alerting.** The scope note left this open on a "less machinery"
  test, and Grafana loses it: rules stay plain PromQL that is reviewable in a diff and testable
  offline with `promtool test rules`, whereas Grafana's provisioned rules are a uid/refId model with
  no offline test harness — and putting the notifier inside the dashboard application means a
  dashboard outage is an alerting outage, which is the opposite of the reason Grafana's public route
  was removed the same day.
- **Email through the node's own Postfix**, to `alerts@reserve-me.ru`, an alias that forwards to both
  the local mbox and the author's real mailbox. This is `adr/0040`'s amendment applied consistently: a
  notification vendor is the same decision the author had just made against for mail, and every reason
  transfers (payment, residency, an account that can lapse). A Telegram bot would additionally add a
  token this deployment does not carry, to reach a channel no more reliable than the mail path already
  running.
- **Five rules.** `ScrapeTargetDown`, `OutboxLagGrowing`, `DeadLetterQueueNotEmpty`, `NodeDiskFilling`,
  `TlsCertificateRenewalOverdue`. The scope list's remaining candidate — "the public endpoints being
  unreachable from outside" — is the external mechanism and is deliberately not among them.
- **`repeat_interval: 24h`**, against Alertmanager's 4-hour default. One unfixable condition at the
  default produces six mails a day, and that is how a channel stops being read.

### How each rule was fired

| Rule | How it was made to fire | Notification |
|---|---|---|
| `ScrapeTargetDown` | **Real, rule untouched.** A scrape target for a hostname that does not resolve was added to Prometheus's config (monitoring configuration only — nothing in the application was stopped), `up == 0` for the full 5 minutes | `[FIRING] ScrapeTargetDown` delivered |
| `DeadLetterQueueNotEmpty` | **Real, rule untouched.** One synthetic message published into `unread-counter.dlq` through RabbitMQ's management API; the queue is consumed by nothing, and it was purged afterwards | `[FIRING] DeadLetterQueueNotEmpty` delivered |
| `OutboxLagGrowing` | Real series, threshold relaxed (`> -1`), 1-minute `for`. Fired for both `ago-chat-api` and `ago-chat-worker`, confirming the `max by (job)` aggregation and the label set | `[FIRING] FireDrill_OutboxLagGrowing` delivered |
| `NodeDiskFilling` | Real series, threshold relaxed to `< 0.80` against a real 75.69% free. Rendered "node root filesystem is 75.69% free" | `[FIRING] FireDrill_NodeDiskFilling` delivered |
| `TlsCertificateRenewalOverdue` | Real series, threshold relaxed to 95 days against a real 89 days remaining. Rendered "expires in 89d 0h 26m 32s" | `[FIRING] FireDrill_TlsCertificateRenewalOverdue` delivered |

Plus a synthetic alert posted straight into Alertmanager's API, which exercised the notification path
by itself and produced both a `[FIRING]` and, five minutes later, a `[RESOLVED]` mail.

Delivery evidence is Postfix's own log: each message `status=sent (delivered to mailbox)` for the
local copy and `status=sent (250 2.0.0 OK ... gsmtp)` for the forwarded one — **accepted by the
receiving provider, which is not the same as landing in an inbox.** Whether they were filed as spam is
the one step only the author can check, and `adr/0040`'s amendment already records why that risk is
real on a cold IP.

The three relaxed rules had their real thresholds covered separately by
`ago-deploy/k8s/overlays/demo/prometheus-alert-rules.test.yml` — `promtool test rules`, every rule
asserted silent one step below and firing one step above, plus a near-miss per rule that must stay
silent (a `loop="compose"` target, a working queue at depth 130, `/boot` at 5% free). Neither half is
sufficient alone: the unit tests cannot see whether a metric exists on the real cluster, and the live
drill could not exercise the real thresholds.

### One thing this needed that did not exist

**`nfr.md` lists "DLQ count" among the required instruments and there is no such instrument.**
`RabbitMqMetrics` counts consumer outcomes as `success`/`error`, which answers a different question —
a transient error is normal at-least-once behaviour, and the one that matters is "is anything parked
right now". This item did **not** add an instrument (`7-08` is working in those repositories, and the
broker already owns the state). It scraped RabbitMQ's own `rabbitmq_prometheus` endpoint instead,
which was already enabled in the image and only needed a port on the Service. An application-side
per-queue gauge would have been a second, lagging copy of something the broker already knows.

### Changed on the node itself

- `/etc/aliases` gained an `alerts:` entry forwarding to the local mbox and the author's mailbox
  (`newaliases` run). Backup at `/etc/aliases.bak-pre-15-03`.
- `kubectl apply -k` of the demo overlay: Alertmanager created; Prometheus and RabbitMQ restarted
  (new config, and a declared `containerPort: 15692`). Nothing else was stopped, scaled, or edited;
  the temporary fire-drill scrape target and rule group were removed afterwards and the synthetic dead
  letter purged.

## Two mechanisms, not one — decided 2026-08-25

Internal alerting and external checking answer different questions, and neither substitutes for the
other. This was implicit and is now stated, because conflating them is how a deployment ends up with
dashboards nobody watches and no idea when it went down.

- **Internal** (this item's rules): outbox lag growing, DLQ rising, disk filling, a pod crash-looping,
  a certificate approaching expiry. Only visible from inside, and worthless if nobody is told.
- **External**: the whole thing being gone. Structurally impossible to detect from inside — a
  deployment cannot alert on its own unreachability, and Grafana in particular runs *inside* the thing
  it watches.

**The external check targets `https://chat.reserve-me.ru/healthz/ready`**, not the landing page and not
the console bundle. `Ago.Chat.Api` registers that endpoint with `ready`-tagged checks for Postgres,
RabbitMQ and Redis, so a 200 there means the API is up *and* its three dependencies are reachable.
Checking a static page instead proves only that nginx served a file, which is green while the API is
dead — the classic mistake that makes monitoring reassuring rather than useful. Verified reachable and
returning 200 from outside on 2026-08-25.

Grafana's own public route was removed the same day (`ago-deploy`'s `gateway.yaml`), which removes any
temptation to treat "I can open the dashboard" as a liveness check.

## Open questions

- **Which external checker.** Three shapes, all defensible, and the choice is the author's:
  a scheduled GitHub Actions workflow (free, no new vendor, genuinely outside the deployment — but
  cron granularity is minutes, GitHub delays scheduled runs under load, and schedules get disabled on
  inactive repositories, so it detects within roughly ten minutes rather than seconds); a third-party
  uptime service (better interval and notification channels, one more vendor, free tiers exist — check
  their current terms rather than trusting a number written here); or a heartbeat pushed outward, where
  silence is the alarm, which keeps working no matter how tightly inbound traffic is firewalled. Not a
  blocker: the internal rules are worth having either way.
