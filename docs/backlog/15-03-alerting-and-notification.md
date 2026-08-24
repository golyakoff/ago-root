# Alerting: rules that fire, and a channel that reaches a person

- **Stage**: 15
- **Status**: ready
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

- [ ] The alerting component is deployed on the demo overlay from a committed manifest.
- [ ] Every rule in the first set has been made to fire deliberately, and the notification arrived.
- [ ] The notification channel's credential comes from the existing Secret mechanism, with only a
      `.example` committed.
- [ ] Each rule has a one-line "what this means, what to check first" entry in the runbook.
- [ ] `7-02` and `7-03`'s out-of-scope notes are updated to point here rather than left contradicting
      the code — `CLAUDE.md`'s "docs are part of the deliverable".

## Open questions

- **External uptime checking.** Every rule above is evaluated *by the deployment being monitored*, which
  by construction cannot tell you it is down. A third-party uptime check is the standard answer and is
  either free-tier or cheap, but it is a real external dependency and the author's call. Not a blocker:
  the internal rules are worth having either way, and this question can be settled after they ship.
