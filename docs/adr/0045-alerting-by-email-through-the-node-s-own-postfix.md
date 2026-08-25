# ADR-0045: Alerting reaches a person by email through the node's own Postfix, evaluated by Prometheus and delivered by Alertmanager

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 15

## Context

Prometheus and Grafana have been deployed since `7-03`, and every instrument `nfr.md`'s Observability
section asks for has existed since `7-02`. Both items explicitly declined alerting with the same
reason — "a demo cluster, not an on-call rotation" — which was true when they were written and stopped
being true at Stage 8, when the deployment became public.

The gap is specific and it is not "we have no rules". It is that **nothing in this deployment tells a
person anything**. A rule that fires into a dashboard nobody has open is not alerting, and the demo has
already lost real time to conditions that were visible and unwatched: the outbox lag gauge existed
while nobody looked at it; a console bundle was a day stale with nothing reporting it; Keycloak's user
store was ephemeral for weeks. So the deliverable is a path from a condition to a human, and evidence
that the path works.

Three constraints bind the choice, and none is new:

- **`adr/0026`'s payment constraint.** The author's Russian-issued cards do not clear at Western
  merchants. A third-party service is not "more expensive"; for many vendors it is unpurchasable.
- **`personal-data.md`'s residency constraint**, which any vendor handling this deployment's data has
  to satisfy.
- **`adr/0040`'s amendment, made hours before this decision.** The author had just weighed a hosted
  mail provider against self-hosting and chosen to self-host entirely — outbound *and* inbound, no
  third-party mail service in either direction, not even a free tier. Postfix runs on the node, signs
  with OpenDKIM, and Keycloak already sends verification mail through it.

And one thing is structural rather than a constraint: **an alerting path that runs on the node cannot
report that the node is gone.** `15-03` separates the two mechanisms explicitly. This ADR is about the
internal one.

## Decision

### 1. Email, through the node's own Postfix, to an alias that forwards to the author

Alertmanager sends to `10.42.0.1:25` — the k3s flannel bridge gateway, the node as seen from inside a
pod — with no SMTP AUTH and no STARTTLS, on exactly the hop and for exactly the reasons `adr/0040`'s
amendment already established for Keycloak: the connection crosses a bridge interface on the same
machine and never leaves it. The consequence worth stating plainly is that **this channel has no
credential at all**, so nothing was added to `overlays/demo/.env`, and `15-03`'s "the credential comes
from the existing Secret mechanism" is satisfied by there being nothing to keep.

Alerts are addressed to `alerts@reserve-me.ru`, an alias in the node's `/etc/aliases` that expands to
two destinations: the local `/var/mail/ago` mbox and the author's real mailbox.

- The **local copy** is the one this repository can name, and it survives an outbound-mail failure —
  so "did anything fire?" has an answer that does not depend on the internet.
- The **human mailbox is in `/etc/aliases` and in no repository.** `CLAUDE.md` forbids putting anyone's
  data in these repositories. Keeping it on the node is also the smaller mechanism: changing who gets
  alerted is one file edit and `newaliases`, with no Secret to regenerate and no pod to restart.

A third-party notifier — Telegram, Slack, ntfy, an uptime service with push — is the decision
`adr/0040` had just made and declined, one day earlier, for reasons that transfer unchanged: payment,
residency, and an account that can lapse or change terms under a deployment expected to sit unattended
for long stretches. A Telegram bot would additionally introduce a real bot token, a credential this
deployment does not currently carry, to reach a channel no more reliable than the mail path that
already exists and is already proven. If a future decision reverses this, it should say what changed
rather than treating the notifier as a different kind of question from the mail sender; they are the
same question.

### 2. Prometheus rules plus Alertmanager, not Grafana's built-in alerting

`15-03` left this open — "if that turns out to be less machinery for one node". It does not.

- Rules stay **plain PromQL in a rule file**, which is reviewable in a diff and unit-testable offline
  with `promtool test rules`. `ago-deploy/k8s/overlays/demo/prometheus-alert-rules.test.yml` asserts
  every rule twice, silent one step below its threshold and firing one step above. Grafana's
  provisioned rules are a UI-shaped model of uids, refIds and reduce/threshold stages, with no offline
  test harness — a format nobody reviews and nothing checks.
- **Grafana is the thing you look at.** Putting the notifier inside the dashboard application means an
  outage of the dashboard is also an outage of the alerting — and this deployment deliberately removed
  Grafana's public route on the same day, to stop "I can open the dashboard" being treated as a health
  check. Alerting belongs on the other side of that line.
- The machinery count does not favour Grafana once both sides are counted: one small static binary and
  one config file here, against provisioning YAML plus contact points plus notification policies plus
  SMTP environment variables on Grafana there.

The cost, stated: one more Deployment and one more PVC on a single 6 GB node, and a second web UI
nobody will open.

### 3. Alerting is a demo-overlay concern, enforced by a glob

Alertmanager and the rule file live in `overlays/demo/`, not in `base/`. Prometheus's config carries
`rule_files: [/etc/prometheus/*.rules.yml]`, and the demo overlay merges the rules into the same
ConfigMap; in `overlays/local` the pattern matches nothing and Prometheus starts with zero rules.
`15-03`'s "the local development cluster gets nothing from this item" is therefore true by
construction rather than by a comment. An Alertmanager in `base/` would appear locally with no Postfix
to reach — an alerting component that cannot deliver, which looks like coverage and is not.

### 4. Five rules, and the shortness is the design

A short list that fires rarely and means something beats a comprehensive one that gets muted. Each
rule below names a failure that has cost this project something or is the single-node failure mode
that takes everything down at once, and each has a section in `runbooks/alerting.md` saying what it
means and what to check first — a rule whose response is unknown is noise.

| Rule | Condition | Where the threshold comes from |
|---|---|---|
| `ScrapeTargetDown` | `up{loop="k8s"} == 0` for 5m | No number to derive. Covers CrashLoopBackOff, a Deployment with no ready replica, and — via the API's `/healthz/ready` — Postgres, RabbitMQ or Redis being unreachable |
| `OutboxLagGrowing` | oldest unpublished row > 60s for 10m | `nfr.md` budgets the outbox dispatch inside a 300 ms p99 for cross-node delivery. 60 s is 200x that, so it cannot be read as slowness |
| `DeadLetterQueueNotEmpty` | any `*.dlq` non-empty for 15m | Zero is the only correct depth for a dead-letter queue, so there is no number to invent |
| `NodeDiskFilling` | root filesystem < 15% free for 30m | **A choice, not a derivation.** `nfr.md` states no disk target. 15% of 79 GB is about 12 GB — room to take a dump and rebuild images while deciding what to delete |
| `TlsCertificateRenewalOverdue` | expiry < 21 days for 1h | cert-manager's own `renewal_timestamp` for this certificate sits exactly 30 days before `not_after`. Under 21 days means renewal has been failing for over a week |

**Not alerted on, deliberately**: latency against `nfr.md`'s p95/p99 targets (those are targets to
validate under load, and the demo carries no load — an alert on a number nobody promised, measured on
traffic that does not exist, fires on noise); SLO burn rate (there is no SLO); consumer error rate
(a transient error is normal at-least-once behaviour and self-heals; one that does not ends up in a
DLQ, so alerting on both means alerting twice for one incident and once for none); queue depth in
general (`OperatorPresenceLost.operator-disconnect-grace` holds a hundred-plus messages at rest by
design); Redis being unavailable as its own rule (`realtime.md` calls it a documented, acceptable
degradation, and `15-03` is explicit that an alert must not blur that line — it is still caught one
level up through the API's readiness probe); and a watchdog alert whose silence is the alarm, which
answers a real question but as a mail every repeat interval forever is precisely what trains a reader
to filter this sender.

### 5. `repeat_interval` is 24 hours, not Alertmanager's 4-hour default

This is the number that decides whether the channel survives contact with a real incident. At four
hours, one condition you already know about and cannot fix today produces six mails a day, and a
channel that does that is a channel you stop reading. Once a day is a reminder.

## Consequences

- **A failure on the public deployment now reaches a person without that person opening Grafana**, for
  the first time. Every rule was made to fire and the mail was observed arriving; the evidence and its
  limits are in `15-03`'s own record.
- **Deliverability is the weak link, and it is inherited rather than introduced.** `adr/0040`'s
  amendment states it: a single VPS IP with no sending history is judged on nothing, blocklist
  monitoring is unowned, and nobody reads `postmaster@` on a schedule. A `250` from the receiving
  provider means *accepted*, not *in the inbox*. The local mbox copy exists so that "did it fire?" has
  an answer that does not depend on any of that.
- **A quiet inbox is not yet evidence of a healthy deployment.** The internal path dies with the node.
  `15-03`'s external check is still an open question, and until it exists this ADR delivers half of
  what "we would find out" means.
- **Two more things to keep correct.** A new rule now needs a runbook section and a promtool test, and
  a change to the metric names those rules read will break them silently until something fires. The
  test file catches renames only if it is run.
- **One more scrape job's worth of cardinality**, from RabbitMQ's per-queue detailed metrics — roughly
  three series per queue, which on this broker is around a hundred series.
- **`adr/0040`'s "wiring `postmaster@` to anything that notifies is `15-03`'s territory, and is not
  done"** is still not done. This ADR builds the notification path; nothing yet watches that mailbox
  for a blocklist complaint. It is now one alias line away rather than a missing mechanism.

## Alternatives considered

- **Grafana's built-in alerting.** Argued above, in decision 2. The "no new pod" argument is real and
  lost to reviewability, testability, and not putting the notifier inside the dashboard.
- **A third-party notification service (Telegram, Slack, ntfy, an uptime service).** Better interval
  and better mobile delivery than email, and several have workable free tiers. Rejected as the same
  decision `adr/0040` had just made against, for the same reasons, plus a bot token this deployment
  would otherwise not carry. Worth revisiting only together with the external-checker question, where
  the "genuinely outside the deployment" property actually earns the vendor.
- **Deliver alerts only to the node's local mbox.** Zero deliverability risk and no personal data
  anywhere. Rejected: nobody reads that mailbox on a schedule — `adr/0040` says so about
  `postmaster@` in as many words — and a notification nobody reads is the exact failure this item
  exists to fix. Kept as the second destination, not the only one.
- **Put the recipient address in `overlays/demo/.env` as a Secret key.** The shape every other setting
  here follows. Rejected: it is not a credential, it is a person's address, and `CLAUDE.md`'s rule is
  about anyone's data rather than about secrets specifically. `/etc/aliases` also makes changing it a
  two-command operation rather than a Secret regeneration plus a pod restart.
- **kube-state-metrics, for a real `CrashLoopBackOff` signal.** The precise metric `15-03` names as a
  candidate. Rejected for now: `up{loop="k8s"} == 0` already catches a crash-looping pod within five
  minutes, by the mechanism that actually matters (its Service has no ready endpoint), and adding a
  cluster-wide metrics exporter to alert on one condition already covered is machinery for its own
  sake on a 6 GB node. It becomes worth it when something needs *which* pod and *why* rather than
  *that the job is down*.
- **postgres_exporter, to alert on deadlocks.** Tempting, because `adr/0037`'s deadlock is exactly the
  kind of thing that cost this project real time. Rejected here: it needs another exporter and another
  database credential, and the deadlock's observable effect on this deployment — a consumer failing
  repeatedly — already lands in a DLQ. A direct deadlock signal is a better rule and should arrive
  with the exporter, not ahead of it.
- **A `predict_linear` disk rule ("full within N days").** The better rule, and deliberately not
  written: `15-05`'s own starting note is that a single hand measurement is the entire growth history,
  and one point is not a slope. A prediction window chosen today would be an invented number wearing
  a function call.
