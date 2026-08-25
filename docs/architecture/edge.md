# Edge: load balancing, ingress, and connection distribution

## What balances what

| Traffic | Balanced by (local k8s) | Balanced by (demo deploy) |
|---|---|---|
| Widget script `ago-chat.js` | Gateway -> static file service | Gateway -> static file service (nginx, `8-02`) - **not** a CDN, see note below |
| REST API calls | NGINX Gateway Fabric -> `Ago.Chat.Api` Service | same, behind the cloud L4 LB |
| WebSocket / SignalR | NGINX Gateway Fabric (HTTP/1.1 upgrade) -> `Ago.Chat.Api` Service | same |
| File upload / download bytes | **nothing** - straight to object storage | same (`file-storage.md`) |
| Internal API -> Worker | nothing - they never call each other synchronously; the broker is the boundary | same |

**Widget script row, updated by `8-02`**: this table originally predicted a CDN for the demo
deployment's copy of the widget bundle. `adr/0026` (accepted after this row was first written)
decided against adding a CDN at all - a new external dependency this single-node, build-on-VPS,
no-registry deployment does not need (the same "no new dependency" instinct that ADR also applied to
image delivery and TLS). `8-02` followed that decision through for the widget script specifically: it
ships from the same kind of lightweight nginx static-file Service the local-k8s column already
named, not a CDN - `ago-widget/Dockerfile`, `ago-deploy/k8s/overlays/demo/demo-shop1-static.yaml`.

**The "no-registry" half of that reasoning expired on 2026-08-25** (`adr/0047`): the three
`Ago.Chat.*` host images are published to GHCR by CI and pulled by the demo overlay. The CDN
conclusion is unaffected — a container registry serves the cluster, not the browser, and nothing about
it puts the widget bundle nearer a visitor. The widget still ships from the nginx Service above, and
its own image is still built on the node under a mutable tag, which `adr/0047` names as the piece
`15-06` could not reach.

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

**Shipped in `3-06`, `Ago.Chat.Api`** (`ago-deploy/k8s/base/api.yaml`): `preStop` sleeps 15s - the
readiness probe's own worst case (`periodSeconds: 5` * `failureThreshold: 3`) before kubelet marks
the pod `NotReady` and the Gateway stops routing to it - and `terminationGracePeriodSeconds` is 45s
(15s `preStop` + `DrainOptions.DrainTimeout`'s 20s + a margin for the rest of the host to actually
stop). Live-verified against the local 3-replica overlay: a real `kubectl rollout restart` cycled
all three pods with zero acknowledged-but-lost messages and zero readiness/liveness flapping once
each new pod was ready (`concurrency.md` has the full run).

**No sticky sessions has a second consequence beyond connection placement**: a SignalR client that
negotiates before connecting sends the negotiate request and the transport upgrade as two separate
HTTP requests, and without affinity the Gateway can route them to two different pods - the second
pod 404s, since it never saw the `connectionToken` the first one handed out. This only showed up
once `3-06` actually ran 3 replicas; every earlier stage's single replica made the two requests
land on the same process by definition. The fix keeps "no sticky sessions" true rather than
special-casing around it: the client skips negotiation and connects with the WebSockets transport
directly (`skipNegotiation: true`, `dev-harness.html`), so the entire handshake is one request and
lands on exactly one pod by construction.

## What the edge is responsible for

- TLS termination, HTTP/2 for REST (WebSockets stay on HTTP/1.1).
- Coarse, cluster-protecting rate limits and connection caps per IP. Per-tenant limits live in the
  application (`caching.md`) because they need domain knowledge. **Live on the public deployment**
  (`k8s/overlays/demo/gateway.yaml`, `gateway.nginx.org/v1alpha1` `RateLimitPolicy`): 30 requests/s
  per IP, burst 60, keyed by `$binary_remote_addr` on the whole Gateway - this stayed a stated
  intent, not an enforced one, until the demo actually went public and a real request-flood test
  confirmed nothing was stopping one (verified live: a 150-request burst from one IP got real `503`s
  once the burst allowance was spent, normal single-request traffic unaffected). Deliberately looser
  than any single application-level limiter (`caching.md`'s `MessageSendRateLimitOptions` etc.),
  since this one fires on every request to every route, not just a specific operation.
- Request size ceilings - trivially small, since bytes do not flow through the API. **Live**
  (`ClientSettingsPolicy`, same file): 1MiB cap on the whole Gateway, verified live with a real 2MB
  body returning `413`.
- Forwarding real client IP (`X-Forwarded-For`), which the app must be configured to trust, or every
  per-IP limit silently applies to the ingress itself.

## Access logging, and the one thing it must not contain

The edge logs every request, which makes it the one component that sees the *whole* request line of a
WebSocket handshake — and a browser's SignalR client has nowhere to put its bearer token on that
handshake except the query string (`realtime.md`; a browser cannot set a header on a WebSocket
upgrade). So the edge's log format is a security decision, not a formatting preference.

Until `17-02` it was neither — nothing in `ago-deploy` configured logging, and NGF's generated config
sets `access_log` only on its own internal server blocks, so **NGINX's compiled-in default applied**:
`combined`, which logs `$request`, the full original request line. Found live rather than assumed: a
successful hub upgrade (`101`) wrote a complete, valid, unexpired visitor JWT to the Gateway's log,
and from there to a file on the node's disk. `coding-style.md` has banned exactly this since it was
written ("Never log message bodies, tokens, presigned URLs...") — the rule simply had never been
applied to a component whose logging nobody had configured.

**Now** (`k8s/overlays/{local,demo}/gateway.yaml`, a Gateway-scoped `NginxProxy` with
`logging.accessLog.format`): the format keeps `combined`'s shape but logs `$uri` — the normalised path,
query string already stripped — in place of `$request`. The whole query string goes rather than the one
known parameter, because redacting by name is a denylist that fails open for the next secret to travel
that way. Both overlays, not just the public one: this is about not writing a secret down, and a local
disk is a disk.

Two limits of that fix, both real:

- **The error log is not covered and cannot be.** nginx's `[error]` lines print `request: "..."` plus
  the full upstream URI, query string included, and neither string is configurable. A *failing* hub
  connect — a 502 during a rolling deploy, an upstream timeout — therefore still writes the token to
  disk. Turning the error level up past `error` would hide those lines along with every upstream
  failure worth seeing. The only real close is moving the token out of the query string, which
  `5-14` and `17-02` both scope out; `17-02` records this as its one open question.
- **Retention is a separate question and still open.** These lines carry client IPs whatever the
  format, and nothing here says how long they are kept — `16-05` owns that.

The trace side of the same request is clean and needs no equivalent rule: the .NET ASP.NET Core
instrumentation redacts query-parameter values by default, so the span carries
`url.query = ?access_token=Redacted`. What protects it is an environment variable staying unset
(`OTEL_DOTNET_EXPERIMENTAL_ASPNETCORE_DISABLE_URL_QUERY_REDACTION`), not any code in this project.

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
