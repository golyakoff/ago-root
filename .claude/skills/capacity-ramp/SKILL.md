---
name: capacity-ramp
description: Find AGO Chat's real concurrent-conversation ceiling on Docker Desktop - bring-up, the NodePort workaround kubectl port-forward cannot survive, cleaning demo_site between runs, and what to watch while it degrades. Use before comparing resource configurations, and every time before re-running the capacity-ramp LoadDriver scenario locally.
---

# Finding the local capacity ceiling

Sibling to `local-cluster` (bring-up, manifests, probes) and `load-test` (scenario design, reporting
discipline). This one is the specific, hands-on playbook for one question: **how many concurrently
open visitor conversations does this deployment's own resource shape carry, and what breaks first** -
worked out live across `load/reports/2026-09-15-local-capacity-ramp.md`'s own three runs, this file is
what that session would have wanted read first.

## The one rule this file exists to enforce

**Clean `demo_site`'s own test data before every comparison run, every time, no exceptions.**
Conversations from an earlier run do not close themselves - they sit in `Waiting` forever, and every
later run starts from an already-degraded baseline that has nothing to do with the resource change
being tested. Found the hard way: two runs against the *identical* configuration landed at step 7
(~3 090 connections) and step 3 (~1 500) back to back - not noise, not the config, `demo_site` had
11 222 leftover `Waiting` conversations from the session's own earlier runs by the time the second one
started. A run compared against a dirty baseline is not a measurement of the thing being tested.

```bash
docker run --rm --entrypoint psql postgres:17-alpine \
  "postgresql://ago:ago-local-dev@host.docker.internal:15432/ago_chat" \
  -c "delete from conversations where site_id = '00000000-0000-0000-0000-000000000001';"
```

Every FK from `conversations` (`messages`, `module_tasks`, `attachments`, `conversation_notes`,
`conversation_tags`, `email_threads`, per `information_schema.referential_constraints` - checked live,
not assumed) is `ON DELETE CASCADE`, so this one statement is enough; nothing else needs deleting by
hand. Confirm with `select count(*) from conversations where site_id = '...'` - should read `0`.

## The broker accumulates too - purge it the same way, every time

Postgres is not the only place a dirty run hides. RabbitMQ's own dead-letter queues and per-consumer
queues (`unread-counter`, `module-task-routing`, `connection-fanout`, `link-identity-command`, and
their own `.dlq`/`.retry` siblings) keep whatever a crashed or forcefully-torn-down earlier run never
finished consuming - and unlike `demo_site`, nothing in this workflow ever drains them on its own.

Found the same way `demo_site`'s own rule was: two runs against the *identical* config and topology
landed at step 8 clean (4 000 connections) and step 2 with a 38.8% error rate at just 1 000 - not the
topology, not noise. `rabbitmqctl list_queues name messages` showed **17 734 messages sitting in
`unread-counter.dlq` alone** (plus similar counts in the other three `.dlq` queues), left over from the
session's own earlier interrupted runs, with a live backlog of 300+ still-queued `MessageAccepted`
messages competing with the fresh run's own traffic the moment it started.

```bash
kubectl exec -n ago-chat deploy/rabbitmq -- rabbitmqctl list_queues name messages
# purge anything non-zero (skip the header rows and the "Timeout:" progress line):
kubectl exec -n ago-chat deploy/rabbitmq -- rabbitmqctl list_queues name messages \
  | awk 'NR>1 && $2>0 && $1!="Timeout:" {print $1}' \
  | while read q; do kubectl exec -n ago-chat deploy/rabbitmq -- rabbitmqctl purge_queue "$q"; done
```

Run this immediately before every comparison run, in the same breath as the `demo_site` cleanup above -
not just once at the start of a session. `OperatorPresenceLost.operator-disconnect-grace` may refuse to
reach zero on its own (a delayed-message queue unrelated to the visitor-message path this scenario
exercises) - that one is not a confound for `capacity-ramp` and is not worth chasing.

## Bring-up

1. Normal `local-cluster` bring-up first (`kubectl apply -k k8s/overlays/local`), then layer
   `k8s/overlays/local-capacity-ramp` on top (`kubectl apply -k k8s/overlays/local-capacity-ramp`) -
   it composes `../local` rather than editing it, so this never changes what a plain local-dev
   session gets. It carries three per-site rate limiters raised (`VisitorSessionRateLimit`,
   `ConversationCreateRateLimit`, `MessageSendRateLimit` - all three, found one at a time by actually
   hitting each one's own stock default) and whatever `postgres` resource/config change is currently
   under test - read that file's own comments before assuming what configuration is live.
2. If images are stale relative to `main` (a real, repeated finding this session - a long-lived local
   cluster drifts fast), rebuild first: `bash k8s/build-images.sh` from `ago-deploy`, then
   `kubectl rollout restart deployment/ago-chat-api deployment/ago-chat-worker deployment/ago-chat-webhooks -n ago-chat`.
3. Seed `demo_site` if this is a genuinely fresh database (fixed ids, idempotent):
   `ago-chat/seed/create-demo-tenant.sh`, or restore its two `insert into sites .../insert into
   operators ...` statements by hand against a port-forwarded `postgres` if the script's own
   `docker-compose` network assumption does not apply to this cluster.

## `kubectl port-forward` cannot carry this load - use a NodePort instead

A real attempt at 300+ concurrent connections through `kubectl port-forward` killed the tunnel outright
(`socat[...] E write(6, ...): Broken pipe`, `error: lost connection to pod`) - it is a debug tool, not
a load path, and every scenario in this file needs a path that survives thousands of connections.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ago-chat-api-loadtest-nodeport
  namespace: ago-chat
  labels:
    purpose: temporary-local-load-test-access
spec:
  type: NodePort
  selector:
    app: ago-chat-api
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30510
EOF
```

Not checked into any overlay - genuinely temporary, `kubectl delete svc ago-chat-api-loadtest-nodeport
-n ago-chat` when done. Point `LOADDRIVER_VISITOR_API`/`LOADDRIVER_OPERATOR_API` at
`http://127.0.0.1:30510` (not `localhost` - see below).

**`localhost` costs every connection an IPv6-then-IPv4 fallback on Windows.** The NodePort listens on
IPv4 only; `curl -6` against it hangs to a timeout, and every one of .NET's own connection attempts
through `localhost` tries `[::1]` first and falls back - measured live: **p50 connect time of 21.1 s**
against `http://localhost:30510`, dropping to **589 ms** against `http://127.0.0.1:30510` on an
otherwise identical run. Always use `127.0.0.1`, never `localhost`, for this driver's own base-URL
env vars.

## Running the scenario

```bash
cd ago-chat
LOADDRIVER_SCENARIO=capacity-ramp \
LOADDRIVER_VISITOR_API=http://127.0.0.1:30510 \
LOADDRIVER_OPERATOR_API=http://127.0.0.1:30510 \
LOADDRIVER_OUTPUT=<path>/capacity-ramp-output.csv \
LOADDRIVER_MARKERS=<path>/capacity-ramp-markers.txt \
dotnet run --project tests/Ago.Chat.LoadDriver -c Release
```

Defaults (`LOADDRIVER_STEP_SIZE=500`, `LOADDRIVER_STEP_COUNT=10`, `LOADDRIVER_STEP_HOLD_SECONDS=60`,
`LOADDRIVER_MAX_ERROR_RATE=0.05`) are a reasonable first pass - narrow the step size once a rough
ceiling is known, rather than guessing a tighter range up front.

## What to watch while it runs

This cluster's own Prometheus scrapes no cAdvisor/container-level metrics (confirmed by querying
`__name__` directly - `container_cpu_usage_seconds_total` and friends are simply absent). `docker
stats` against the real container names is the fallback, and it is enough:

```bash
docker stats --no-stream $(docker ps --format "{{.Names}}" | grep k8s_postgres_postgres)
docker stats --no-stream $(docker ps --format "{{.Names}}" | grep -E "ago-chat-api|ago-chat-worker")
```

- **`PIDS` count matching `pg_stat_activity`'s own row count exactly** is the live proof PostgreSQL is
  process-per-connection, not thread-pooled - worth confirming once, cheaply, before reasoning about
  where its own CPU is going.
- A pod's own `RESTARTS` column climbing *during* a run, cross-referenced against `kubectl get events
  --sort-by='.lastTimestamp' | grep -i unhealthy` - the two failure shapes this session found look
  different in the events (`Container ... failed liveness probe` vs. an unhandled exception in a pod's
  own `--previous` logs) and mean different things: one is the pod going too slow to answer its own
  health check, the other is a real crash.
- For "why is CPU actually saturating" past "it is saturating" - `dotnet-trace` on a bare local
  instance (`DOTNET_PROCESSOR_COUNT=1` to emulate a 0.5-1 CPU pod quota), profile
  `dotnet-sampled-thread-time` (not `cpu-sampling` - that one is Linux-only, `collect-linux`, not
  available through plain `dotnet-trace collect` on Windows). A `UNMANAGED_CODE_TIME`/`CPU_TIME` split
  far toward the former means the process is blocked/waiting, not computing - a real, different
  diagnosis than "needs a faster method", and this session's own trace (97.75%/2.25%) is what pointed
  at a connection-count ceiling instead of a CPU-bound one.

## Reporting

Same discipline `load-test`'s own skill states generally, restated for what this specific procedure
tends to produce: a report that only shows the clean run and the final failure is not the whole
method. Keep the failed setup attempts (stale images, the port-forward collapse, a dirty database) in
the report - each one was itself a finding, and the next person to run this needs them named, not
silently avoided.
