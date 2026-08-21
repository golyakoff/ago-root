# Graceful shutdown: drain, readiness-vs-liveness, real preStop

- **Stage**: 3
- **Status**: ready
- **Depends on**: `3-01-connection-registry.md`, `3-02-targeted-fanout-delivery.md` - draining
  means telling clients to reconnect (needs `3-03`'s `reconnect(after:)` hub method) and cleaning
  up registry entries (needs `3-01`), so this is naturally last: it is also where Stage 3's whole
  "three replicas" claim gets its real, live proof.

## Goal

`Ago.Chat.Api` under `SIGTERM` stops accepting new connections, tells existing clients to
reconnect, drains, and exits cleanly within `terminationGracePeriodSeconds` - a rolling deploy or
scale-down costs only a reconnect, never a lost or corrupted message (`concurrency.md`'s shutdown
sequence, `edge.md`'s Rolling deploys section). Readiness reflects real dependency health and goes
false during drain while liveness stays true, matching what `2-04` already proved for `Worker`.

## Context to read first

`docs/architecture/concurrency.md`'s Graceful shutdown section, `edge.md` in full (Rolling deploys,
Health probes sections), `2-04`'s backlog item (the precedent for what "readiness means dependencies
reachable" looks like, already shipped for `Worker`'s `PostgresHealthCheck`/`RabbitMqHealthCheck`).

## Scope

- `Ago.Chat.Api`'s health checks stop being trivially-healthy stand-ins: readiness reflects
  Postgres, RabbitMQ, and Redis reachability (mirroring `Worker`'s `PostgresHealthCheck`/
  `RabbitMqHealthCheck` pattern, plus a new Redis check), and additionally goes false the moment
  drain begins - liveness never does (`edge.md`: "conflating the two makes Kubernetes kill a pod
  that is deliberately shedding load").
- `IHostApplicationLifetime.ApplicationStopping` handler: stop accepting new hub connections, send
  `reconnect(after: jitteredDelay)` (`3-03`'s stub, now a real caller) to every connection this node
  owns, delete this node's registry entries (`3-01`), wait for connections to actually drop or a
  bounded timeout, then let the host stop.
- `ago-deploy/k8s/base/api.yaml`: real `preStop` timing (currently a placeholder `sleep 5` with a
  comment saying so) and `terminationGracePeriodSeconds` that genuinely exceeds `preStop` + drain
  time - tune both from what this slice's own testing shows, not a guess.
- Bump `Ago.Chat.Api`'s `replicas` to 3 in the local overlay and verify `least_conn` balancing is
  actually configured on the Gateway (`edge.md` names it as the algorithm; `adr/0014`'s NGF install
  is what would carry it - check whether the current `Gateway`/`HTTPRoute` needs a policy
  attachment for this or gets it by default).

## Out of scope

- Reconnect-storm behaviour under real load - Stage 7, per `edge.md`'s own note.
- `Worker`/`Webhooks` shutdown - `Worker`'s is already proven (`2-04`'s `UnreadCounterShutdownTests`);
  `Webhooks` has no real dependency to drain yet.

## Done when

- [ ] `kubectl rollout restart deployment/ago-chat-api -n ago-chat` under a synthetic load
      (matching `k8s-local.md`'s own suggested cheapest drain test) produces zero
      acknowledged-but-lost messages and zero readiness/liveness flapping - run for real against
      the local cluster with 3 replicas, not asserted from unit tests alone (`k8s-local.md`: "What
      to check after a change").
- [ ] `Ago.Chat.Concurrency.Tests`: killing one node mid-conversation - the other two still serve
      that conversation correctly once the client reconnects (the direct proof of Stage 3's "three
      Api replicas serve one conversation correctly").
- [ ] `Ago.Chat.Integration.Tests`: readiness reports unhealthy the instant drain starts, while
      liveness stays healthy throughout - the two-signal claim, checked, not just wired.
- [ ] `docs/architecture/concurrency.md` and `edge.md` get the "shipped" treatment for the Api
      shutdown path specifically (the general sequence was already documented pre-Stage-3; this
      closes the gap between documented intent and what `Ago.Chat.Api` actually does).
- [ ] `docs/runbooks/k8s-local.md` updated if anything about the bring-up sequence changes with 3
      replicas (health-check timing already has a "known issues" precedent there worth following
      if something new turns up).

## Open questions

None - this closes out what every earlier Stage 3 doc reference already promised was coming.
