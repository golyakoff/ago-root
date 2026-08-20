# Edge: load balancing, ingress, and connection distribution

## What balances what

| Traffic | Balanced by (local k8s) | Balanced by (demo deploy) |
|---|---|---|
| Widget script `widget.js` | Gateway -> static file service | CDN, long-cached, versioned filename |
| REST API calls | NGINX Gateway Fabric -> `Ago.Chat.Api` Service | same, behind the cloud L4 LB |
| WebSocket / SignalR | NGINX Gateway Fabric (HTTP/1.1 upgrade) -> `Ago.Chat.Api` Service | same |
| File upload / download bytes | **nothing** - straight to object storage | same (`file-storage.md`) |
| Internal API -> Worker | nothing - they never call each other synchronously; the broker is the boundary | same |

On Docker Desktop the entry point is **NGINX Gateway Fabric**, configured through the Gateway API
(`Gateway`, `HTTPRoute`) rather than a legacy `Ingress` resource, reachable on `localhost`. Nothing in
the application depends on which controller is in front, and no route or policy attachment may encode
business behaviour - if a rule matters, it belongs in code where it can be tested. NGF is the direct
successor to `ingress-nginx`, which was archived in March 2026 with no further releases; `adr/0014`
has the full reasoning.

## The load balancing decision that matters: no sticky sessions

The obvious way to scale SignalR is sticky sessions (or Redis backplane + sticky). We deliberately
do not:

- A visitor's connection may land on **any** `Api` replica. The replica registers ownership of that
  connection in Redis (`realtime.md`).
- Delivery to a connection is routed by looking that ownership up, then sending the event to the
  owning node through the broker.
- Therefore a rolling deploy, a scale-down, or a killed pod costs a reconnect, and nothing else.
  There is no session affinity to lose and no state to migrate.

The cost is honest and should be stated in the README: every cross-node delivery pays one broker hop,
which shows up in end-to-end p95. That is measured in Stage 7, not hand-waved.

`least_conn` is the balancing algorithm for the API service: with long-lived WebSockets, round-robin
distributes *connection events* evenly while leaving *connection counts* badly skewed after any
partial outage - the pod that was down comes back with zero connections and round-robin will not
prefer it.

## Rolling deploys without dropping conversations

1. Pod gets `SIGTERM`, readiness probe starts failing, ingress stops sending new connections.
2. `preStop` hook sleeps long enough for the ingress to notice (readiness propagation is not
   instant - this sleep is the difference between a clean deploy and a burst of 502s).
3. The app tells its connected clients to reconnect, then drains (`concurrency.md`).
4. Clients reconnect with exponential backoff **plus jitter**, land on other replicas, and resume
   from their last known `sequence`. Without jitter, a rolling restart becomes a self-inflicted
   thundering herd; this is a scenario in the Stage 7 load test.

`terminationGracePeriodSeconds` must exceed `preStop` + drain time, otherwise Kubernetes kills the
pod mid-drain and the "no loss after ack" guarantee becomes a lie.

## What the edge is responsible for

- TLS termination, HTTP/2 for REST (WebSockets stay on HTTP/1.1).
- Coarse, cluster-protecting rate limits and connection caps per IP. Per-tenant limits live in the
  application (`caching.md`) because they need domain knowledge.
- Request size ceilings - trivially small, since bytes do not flow through the API.
- Forwarding real client IP (`X-Forwarded-For`), which the app must be configured to trust, or every
  per-IP limit silently applies to the ingress itself.

## What the edge must **not** be responsible for

Auth decisions, CORS logic that depends on a site's `allowed_origins` (that is a database lookup,
so it belongs in the app), routing based on tenant, or anything requiring knowledge of a
conversation. An ingress annotation is invisible to tests and to a code reviewer.

## Health probes

- **Liveness**: process is alive and its background loops have not deadlocked.
- **Readiness**: dependencies reachable *and* the node is willing to accept new connections. During
  drain, readiness goes false while liveness stays true - conflating the two makes Kubernetes kill a
  pod that is deliberately shedding load.
- **Startup**: migrations applied / caches warmed before traffic arrives.
