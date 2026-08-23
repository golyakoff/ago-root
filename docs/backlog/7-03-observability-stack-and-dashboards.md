# Prometheus, Grafana and Jaeger in deploy/, with real dashboards checked in

- **Stage**: 7
- **Status**: ready
- **Depends on**: `7-01` (traces to receive), `7-02` (metrics to scrape)

## Goal

After this, `docker-compose up` and the local Kubernetes cluster both bring up Prometheus (scraping
all three `Ago.Chat.*` hosts' `/metrics`), Jaeger (receiving OTLP traces directly, per `7-01`'s ADR),
and Grafana with dashboards already provisioned and checked into `deploy/` — nobody hand-builds a
panel to read a Stage 7 load-test result; the dashboards already exist and already show real data the
first time the stack comes up.

## Context to read first

`naming-and-structure.md`'s `ago-deploy` layout (`docker/`, `k8s/base/`, `k8s/overlays/local/`) — the
same pattern as every existing service in `deploy/k8s/base/` (`postgres.yaml`, `redis.yaml`,
`keycloak.yaml`, …). `deploy/docker/docker-compose.yml` itself, to match its existing
healthcheck/restart/volume/naming conventions exactly rather than inventing a new style (the `keycloak`
service's own comments already explain two such conventions worth following — idempotent
config-import, and where a shared file the compose loop reaches into actually lives so there is only
one copy). `nfr.md`'s Observability requirements section — every dashboard panel this item ships exists
because a line in that section demands it, not because it looks good. `7-01`'s ADR for the exact OTLP
endpoint Jaeger needs to expose. The `local-cluster` skill for how the existing infra services are
brought up and verified live, not just applied.

## Scope

- `deploy/docker/docker-compose.yml`: add `prometheus`, `grafana`, `jaeger` services, matching this
  file's existing healthcheck/restart/volume conventions.
- `deploy/k8s/base/`: `prometheus.yaml`, `grafana.yaml`, `jaeger.yaml` (workload + service + probes,
  matching `postgres.yaml`'s own shape), wired into `kustomization.yaml`.
- Prometheus scrape config targeting each host's `/metrics` endpoint (`Api`, `Worker`, `Webhooks` — the
  `Webhooks` target is scrapeable even before `6-05` ships real logic, since `7-01`/`7-02`'s bootstrap
  is host-wide, not feature-gated).
- Grafana: provisioned via config files checked into `deploy/` (not hand-clicked), datasources
  (Prometheus, Jaeger) pre-wired, and dashboards — one per `nfr.md` concern area is the natural split:
  **Ingest & delivery** (RED per hub/consumer, latency targets overlaid as threshold lines),
  **Pipeline internals** (queue depth, channel occupancy, batch histogram, outbox lag), **Resilience**
  (breaker state, bulkhead rejections, DLQ count), **Connections & assignment** (per-node connections,
  assignment attempts vs. conflicts), **Cache** (hit ratio per namespace).
- A short section added to `runbooks/local-dev.md` and `runbooks/k8s-local.md` (both already-existing
  per `CLAUDE.md`'s table) pointing at the new Grafana URL and default credentials — `CLAUDE.md`'s
  "everything is public" rule means no real credentials; a documented local-only default is fine,
  matching how `keycloak`'s admin user/password already work in the same compose file (env-var-driven,
  no committed secret value).

## Out of scope

- Actually populating the dashboards with load-test data — `7-04`/`7-05` generate the traffic that
  makes them show something meaningful; this item's Done-when only requires that a panel resolves to a
  real, non-empty query against a few seconds of idle-cluster data.
- Long-term metric retention/storage sizing — a demo cluster restarts often; Prometheus's default local
  retention is enough, and tuning it without a real multi-day usage pattern would be inventing a number
  `CLAUDE.md` already forbids.
- Alerting (Alertmanager) — not asked for anywhere in `roadmap.md` or `nfr.md`.

## Done when

- [ ] All three new services come up healthy in both the compose loop and the Kubernetes overlay,
      verified live (`local-cluster` skill's own bar — "verified" means actually run, not assumed from
      the manifest).
- [ ] Prometheus's own targets page shows all three `Ago.Chat.*` hosts as `UP`.
- [ ] Every dashboard panel resolves to a real, non-empty query against a running (even idle) cluster —
      no panel referencing a metric name `7-02` did not actually ship.
- [ ] A trace sent by `7-01`'s own integration test (or a manual send) is visible in Jaeger's UI,
      confirmed live.
- [ ] `runbooks/local-dev.md` and `runbooks/k8s-local.md` updated with the new URLs.

## Open questions

None.
