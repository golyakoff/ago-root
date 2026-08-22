# Graceful shutdown: drain, readiness-vs-liveness, real preStop

- **Stage**: 3
- **Status**: done
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

- [x] `kubectl rollout restart deployment/ago-chat-api -n ago-chat` under a synthetic load
      (matching `k8s-local.md`'s own suggested cheapest drain test) produces zero
      acknowledged-but-lost messages and zero readiness/liveness flapping - run for real against
      the local cluster with 3 replicas, not asserted from unit tests alone (`k8s-local.md`: "What
      to check after a change").
      **Verified live**: a single visitor held one hub connection through the Gateway while a real
      `kubectl rollout restart` cycled all 3 `ago-chat-api` pods, sending 25 messages at the
      sustained per-visitor rate limit (`3-05`). 25/25 acked and confirmed present in the final
      history, exactly 1 disconnect/reconnect as its pod was replaced, resumed correctly via
      `lastKnownSequence`. All 3 final pods `RESTARTS: 0`; the only `Unhealthy` events were the
      normal pre-ready startup cycle, not flapping of an already-ready pod. `least_conn` confirmed
      directly in the Gateway's own generated NGINX config (`upstream ago-chat_ago-chat-api_80 {
      least_conn; ... }`, 3 `server` lines). Getting this running for real (not just unit-tested)
      found and fixed two more real bugs beyond the drain mechanism itself, both were blocking any
      multi-replica traffic at all: each `Ago.Chat.Api` replica signed JWTs with its own random
      per-process key (fixed: `Auth:SigningKey`, shared via the same `infra-credentials` mechanism
      Postgres/RabbitMQ already use), and a SignalR client's negotiate-then-upgrade handshake needs
      same-pod affinity the Gateway does not provide (fixed: `skipNegotiation` + WebSockets-only
      transport in `dev-harness.html`, removing the need for that affinity entirely). The Gateway's
      `HTTPRoute` also only carried `/healthz` before this item - `/api` and `/hubs` were added,
      since proving any of the above needs real hub traffic through the Gateway, not just health
      checks. Full detail in `concurrency.md` and `edge.md`.
- [x] `Ago.Chat.Concurrency.Tests`: killing one node mid-conversation - the other two still serve
      that conversation correctly once the client reconnects (the direct proof of Stage 3's "three
      Api replicas serve one conversation correctly").
      `NodeDeathReconnectTests.VisitorsNodeDies_TheyReconnectToADifferentNode_AndResumeCorrectly_WhileTheOperatorsNodeIsUnaffected`
      - a visitor on node A starts a conversation, an operator on node B assigns and sends a
      message, node A runs a real `ConnectionDrainCoordinator.StopAsync`, the visitor reconnects on
      node C and resumes with the operator's message intact, node B's own registry entry is
      untouched throughout. Green, 5/5 consecutive runs.
- [x] `Ago.Chat.Integration.Tests`: readiness reports unhealthy the instant drain starts, while
      liveness stays healthy throughout - the two-signal claim, checked, not just wired.
      `DrainReadinessTests` - `DrainHealthCheck` flips `Healthy` -> `Unhealthy` the instant
      `DrainState.MarkDraining()` runs, and the liveness predicate (`_ => false`) is asserted
      directly against a `"ready"`-tagged registration, so it can never see `DrainHealthCheck`.
- [x] `docs/architecture/concurrency.md` and `edge.md` get the "shipped" treatment for the Api
      shutdown path specifically (the general sequence was already documented pre-Stage-3; this
      closes the gap between documented intent and what `Ago.Chat.Api` actually does).
- [x] `docs/runbooks/k8s-local.md` updated if anything about the bring-up sequence changes with 3
      replicas (health-check timing already has a "known issues" precedent there worth following
      if something new turns up).
      Updated: 3 replicas by default now, `AUTH_JWT_SIGNING_KEY` in the overlay's `.env`, migrations
      and seeding verified against this cluster's own Postgres for the first time (previously only
      claimed for `docker-compose`), `/api`/`/hubs` routing, and a `least_conn` live-check recipe.

A real correctness bug was also found and fixed along the way, unrelated to drain but found by the
same test: `ConnectionDrainCoordinator` registered its `ApplicationStopping` handler inside
`ExecuteAsync`, which races a shutdown that starts immediately after `StartAsync` returns
(`BackgroundService.StartAsync` returns once `ExecuteAsync` is *scheduled*, not once it has run).
Fixed by moving the registration to a field initializer, which runs synchronously during
construction. See `concurrency.md` for detail.

## Open questions

None - this closes out what every earlier Stage 3 doc reference already promised was coming.
