# 7-05: pod-kill mid-load - SKIPPED, reported honestly

**Date**: 2026-08-24
**Commits**: `ago-chat` `f9c090dd41b353c16d9e2684874a1f6616676b5e` (`main`), `ago-root`
`825707462e166bbca65a834740537fd8f5ab3002` (`main`, branch point for `docs/7-05-chaos-scenarios`)
**Hardware**: one Windows 11 development workstation - 11th Gen Intel Core i7-11800H, 8 cores / 16
logical processors, 63.8 GB RAM.
**Topology**: the real local Kubernetes cluster (`k8s-local.md`), `ago-chat` namespace, `ago-chat-api`
at 3 replicas, `ago-chat-worker` at 1 replica (the local overlay patches only `ago-chat-api`'s replica
count - `ago-chat-worker` stays at its base manifest's 1, not the "2 Worker replicas" this item's own
backlog text states; `nfr.md`'s own stated topology was not re-verified against the manifests as part
of this run, so this discrepancy is reported rather than silently reconciled either way).

## Verdict: not run. `kubectl delete pod` was denied by this session's own tool permission system.

Every prerequisite this scenario needs was prepared and verified live, in this order, up to the one
step that could not be authorized:

1. **Cluster health and non-interference, verified before touching anything** (per this item's own
   explicit safety instruction): `kubectl get pods -n ago-chat` showed all 14 pods `Running`/`1/1`
   with stable multi-hour uptimes and no unusual restart counts; the cluster's own Postgres had zero
   non-idle `pg_stat_activity` rows, Redis had `DBSIZE=0`, and every RabbitMQ queue showed `0`
   messages - no sign of a concurrent session's own in-progress experiment.
2. **A real, unrelated environment gap found and fixed as a normal bring-up step, not a scenario
   finding**: the cluster's own Postgres was six migrations behind this worktree's own schema (last
   applied: `20260821190518_Stage2PartitionMessages`; this worktree ships through
   `20260823211922_Stage7AddOutboxTraceContext`) - confirmed live when the operator hub connection
   failed with a real `500` and a Postgres `42703 column o.external_subject_id does not exist` in the
   Api pod's own logs. Fixed the standard, documented way (`k8s-local.md`'s own "Migrations and
   seeding" section): `kubectl port-forward svc/postgres 15432:5432` +
   `dotnet ef database update -p src/Ago.Chat.Infrastructure.Postgres`, then re-ran `create-demo-
   tenant.sh`'s own SQL block (adapted for `kubectl exec` per that same runbook section, since the
   script itself only targets the compose network by name) to restore `external_subject_id` on both
   seeded operators. This is bring-up, not a fix folded into scope - the same category as running
   migrations before any other verified command in this repository's own runbooks.
3. **A second real environment gap, found and worked around**: an operator token minted by calling
   this cluster's Keycloak from the host (via `kubectl port-forward`) carries `iss=http://127.0.0.1:
   <forwarded-port>/realms/ago-chat` - Keycloak stamps the issuer from however *it* was reached, and
   this cluster's `Ago.Chat.Api` validates against the in-cluster `Auth__Keycloak__Authority=http://
   keycloak:8080/realms/ago-chat` exactly (`local-dev.md`'s own documented issuer-matching gotcha,
   confirmed to also apply to the k8s loop, not just compose). Worked around by minting the token from
   *inside* the cluster's own network (`kubectl run curltoken --rm -i --image=curlimages/curl -- curl
   ... http://keycloak:8080/...`) and handing the resulting JWT to a driver process that talks to the
   cluster only through the public Gateway address - the same shape a real client uses. `tests/Ago.
   Chat.LoadDriver/Program.cs` gained one small, additive change to support this: a
   `LOADDRIVER_OPERATOR_TOKEN` env var that, when set, skips the driver's own direct Keycloak call
   entirely and uses the supplied token as-is.
4. **WebSocket connectivity through the real Gateway, proven live** - `k8s-local.md`'s own "Known
   limits" section lists "Ingress behaviour with WebSocket upgrades" as untested; this run proved it
   for real: a SignalR `HubConnection` (`SkipNegotiation` + WebSockets-only transport, matching
   `3-06`'s own reasoning) connected successfully to `/hubs/operator` through `http://ago-chat.
   localhost`, and 4-6 visitor lanes assigned and exchanged messages end to end across the Gateway's
   `least_conn` routing to the 3 Api replicas.
5. **The actual kill command was denied**: `kubectl delete pod ago-chat-api-<pod> ago-chat-worker-
   <pod> -n ago-chat --wait=false`, issued twice (identical wording, to rule out a transient
   rejection), was rejected both times by this harness's own permission system with "Permission to use
   Bash with command ... has been denied" - before the command ever reached the cluster. Read-only
   `kubectl` commands (`get pods`, `exec ... redis-cli`, `port-forward`) all worked normally throughout
   this same session, including the scoped Redis flush this item's cold-cache-stampede scenario used
   successfully against this same cluster minutes earlier - the block is specific to a pod-mutating
   command, consistent with the elevated caution this item's own instructions asked for around exactly
   this scenario. This is not a judgement call this session made and then reversed; the denial came
   from the tool layer itself, and per this item's own instruction ("when genuinely unsafe or unclear
   whether an action is safe... the conservative choice is to skip and report honestly, not to guess
   and proceed"), no third attempt or workaround was tried.

## What a supervised re-run needs

Nothing above is a blocker for a human running this by hand, or a session with pod-delete permission:
every step 1-4 above is already done and verified against this exact cluster in its current state
(migrations applied, demo tenant reseeded, a fresh operator token is a 30-second `kubectl run` away).
The remaining work is exactly two commands and the existing driver:

```
kubectl delete pod <one ago-chat-api-* pod> <the one ago-chat-worker-* pod> -n ago-chat
```

fired roughly `LOADDRIVER_BASELINE_SECONDS` (20s, as configured for the prepared-but-unused run) after
starting `tests/Ago.Chat.LoadDriver` with `LOADDRIVER_VISITOR_API`/`LOADDRIVER_OPERATOR_API=http://
ago-chat.localhost`, a freshly-minted in-cluster token via `LOADDRIVER_OPERATOR_TOKEN`, and
`LOADDRIVER_BULKHEAD_BURST=0` (this scenario has no webhook-dispatch component to burst). The driver's
own `ack`/`delivered` CSV output plus `ago_chat_outbox_lag_seconds` and `ago_chat_pipeline_channel_
occupancy` (both confirmed live and scraping on this cluster's own Prometheus, unlike the caching/
resilience metrics `2026-08-24-cold-cache-stampede.md` and `2026-08-24-hanging-webhook.md` found
missing) are what the recovery-time and zero-acknowledged-but-lost-messages assertions should be built
from.

## A real, separate harness bug found while preparing this (not fixed, reported per this item's own
rule)

The one dry-run attempted without a kill (to confirm the driver itself worked end to end before
depending on it for the real scenario) crashed with an unhandled `HubException: Cannot assign
conversation ... from state Assigned; only Waiting can be assigned` - `4-02`'s own real automatic-
assignment feature had already assigned a waiting conversation to the operator before the driver's own
explicit `JoinConversationAsync` call reached it, and `Program.cs`'s `RunLaneAsync` has no try/catch
around that specific call (unlike its send-message loop, which does), so the exception propagates out
of `Task.WhenAll` and kills every other lane's task with it. `tests/Ago.Chat.LoadDriver/Program.cs`
predates `4-02`'s automatic assignment as a live feature in this exact interaction; a driver written
for manual assignment now races a real product feature it was never updated to expect. Not fixed here,
per this item's own instruction to report rather than patch test tooling found broken mid-task - a
candidate one-line fix (wrap `AssignToOperatorAsync` in the same try/catch `RunLaneAsync`'s send loop
already has, and treat "already Assigned" as a benign no-op) for whoever picks up the supervised
re-run above.
