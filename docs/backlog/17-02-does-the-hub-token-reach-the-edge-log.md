# Does the hub token reach the edge access log, or the traces?

- **Stage**: 17
- **Status**: done — **the access log: yes, in full. The traces: no, already redacted.** Both answers
  were read off a running system on 2026-08-25, not derived from configuration. The access log is
  fixed (`ago-deploy/k8s/overlays/{local,demo}/gateway.yaml`, an `NginxProxy` whose
  `logging.accessLog.format` drops the query string); the trace side needed no change, and that
  "needed no change" is itself the result worth keeping, since the next person would otherwise
  re-derive it from the same plausible-looking defaults. One residual is left open on purpose and
  named below: nginx's **error** log still carries the query string and cannot be told not to.
- **Depends on**: nothing. Complements `5-14-fix-signalr-logs-access-token-to-console.md` rather than
  extending it: that item fixes the browser clients, which is a one-line change in two repositories;
  this one answers the server-side half that item explicitly declined, which is verification work
  against a running deployment.

## Goal

A definite, written answer to whether a live operator or visitor bearer token is being persisted
server-side, and the fix if it is. `5-14` found the token printed in the browser console and states,
correctly as far as it goes, that "`Ago.Chat.Api` is not implicated by this finding". The API's own
logger genuinely is not — but the API's logger is not the whole server side, and two places that
would matter considerably more have never been looked at.

The distinction is worth stating plainly, because it is the reason this item exists at all: a token in
a browser console is exposed to whoever is at that browser, and it disappears when the tab closes. A
token in an access log is written to disk, kept for as long as nothing rotates it, and — once
`15-02`'s backups exist — copied off the node.

## What is already known

- **Confirmed, `5-14`**: both SignalR clients print the negotiated WebSocket URL with `access_token`
  in it, at the library's default level, because neither calls `configureLogging`.
- **Confirmed clean, checked while writing this item**: `Ago.Chat.Api`'s own logging.
  `appsettings.json` sets `"Microsoft.AspNetCore": "Warning"`, which suppresses the request-starting
  log that would otherwise print path and query at `Information`. This is the first place anyone would
  look, and it is fine — worth recording so nobody re-checks it.
- **Not a defect, and not being changed**: the token travelling in the query string. A browser cannot
  set a header on a WebSocket handshake, so `?access_token=` is the standard SignalR pattern, and
  `Ago.Chat.Api` already accepts it only on the two hub paths (`HubTokenFromQueryString` in
  `Program.cs`). `5-14` reaches the same conclusion and scopes the alternative design out; this item
  agrees and does not reopen it.

## What was found (2026-08-25, local cluster, `runbooks/k8s-local.md`)

### 1. The edge access log — the token was there, in full

Confirmed, and the mechanism is exactly the one this item guessed at, one layer deeper than expected.
`ago-deploy` sets no `access_log` and no `log_format` anywhere, and neither does NGINX Gateway
Fabric's own generated config — the `http {}` block contains no `access_log` directive at all, only
`access_log off;` on NGF's four internal server blocks (the stub-status socket, the `:8081` readiness
server, and the 500/503 error sockets). So **NGINX's compiled-in default applies**: `nginx -V` in the
data-plane image reports `--http-log-path=/var/log/nginx/access.log`, that path is a symlink to
`/dev/stdout`, and the default format is `combined`. `combined` logs `$request` — the *full original
request line*, query string included.

Read after a real hub connection through the Gateway, with the token replaced here and nowhere else:

```
<client-ip> - - [25/Aug/2026:12:44:49 +0000] "GET /hubs/visitor?access_token=<REDACTED> HTTP/1.1" 101 107 "-" "-"
```

The `101` is the point: that is a *successful* WebSocket upgrade, so this is the ordinary path every
connection takes, not an error case. The `<REDACTED>` stood for a complete, valid, unexpired visitor
JWT.

**It reaches disk, not just a stream.** Traced the whole chain on the node rather than assuming it:
nginx writes to `/dev/stdout`, the container runtime captures that into
`/var/lib/docker/containers/<id>/<id>-json.log`, and `/var/log/pods/ago-chat_ago-chat-gateway-nginx-*/nginx/0.log`
is a symlink to it. Confirmed by finding an access-log line from a specific connection in that file
by hand.

**Fixed** in both overlays with a Gateway-scoped `NginxProxy` (`logging.accessLog.format`) that keeps
`combined`'s shape but logs `$uri` instead of `$request` — `$uri` is the normalised request path with
the query string already stripped, and no route in either overlay uses a URLRewrite filter, so it is
the path the client actually asked for. Re-verified with the same client afterwards: same successful
`101`, and the line reads `"GET /hubs/visitor HTTP/1.1"`, with zero occurrences of a JWT anywhere in
the Gateway's log.

Two choices in that fix worth recording, since both had a plausible alternative:

- **The whole query string goes, not just `access_token`.** Redacting one named parameter is a
  denylist — it protects the value we already know about and fails open for the next one. Nothing
  this API does needs the query string in a request log; the path, status and client address are what
  a request log is for, and anything finer belongs in a trace.
- **A Gateway-scoped `NginxProxy`, not the GatewayClass-scoped one** the NGF install ships. NGF merges
  the two field-by-field with the Gateway's winning, so setting one field here does not discard the
  install's image/replica/Service settings — verified live, the data-plane Service stayed
  `LoadBalancer` on `localhost` after attaching it. This keeps the change inside `ago-deploy` instead
  of turning it into a per-machine install step in the runbook.

**`SnippetsPolicy` was tried first and does not work on a default NGF install.** The CRD is present
(the CRD bundle installs it), but the controller does not watch it unless snippets are explicitly
enabled, so a policy applies cleanly, gets no status, and silently does nothing. Worth knowing before
reaching for it: a snippet that appears accepted is not a snippet that is in the config. Check
`/etc/nginx/conf.d/http.conf` in the data-plane pod, not the object's own existence.

### 2. The trace spans — clean already, and the reason is worth keeping

Not a leak. Read the real `GET /hubs/visitor` server span in Jaeger for a connection made seconds
earlier:

```
http.request.method = GET       http.response.status_code = 101
http.route          = /hubs/visitor
url.path            = /hubs/visitor
url.query           = ?access_token=Redacted
otel.scope.name     = Microsoft.AspNetCore
```

`Redacted` there is OpenTelemetry's own output, not this document's editing. The .NET ASP.NET Core
instrumentation redacts query-parameter *values* by default; the attribute name survives so the shape
of the request is still legible, and the value never leaves the process. `AddAspNetCoreInstrumentation()`
being called with no filter (`Ago.Platform.Hosting/ServiceCollectionExtensions.cs`) is therefore fine
as it stands, and **no `Ago.Platform.*` change was made** — so no `CHANGELOG.md` entry and no version
bump either.

The thing to guard is not the code but an environment variable: setting
`OTEL_DOTNET_EXPERIMENTAL_ASPNETCORE_DISABLE_URL_QUERY_REDACTION` turns this off. It is set nowhere in
`ago-deploy`, `ago-platform` or `ago-chat` today — checked — and it must stay that way. That is the
whole defence, and it is one grep, which is why it is written down here.

### 3. The residual this does not close: nginx's error log

`access_log` format has no effect on the **error** log, and nginx's error-log lines are not
configurable at all. Measured deliberately rather than reasoned about: a request forced to 502 through
this Gateway produced

```
[error] ... upstream prematurely closed connection ..., request: "GET /errtest?access_token=<FAKE> HTTP/1.1",
upstream: "http://<pod-ip>:5432/errtest?access_token=<FAKE>", host: "ago-chat.localhost"
```

— the query string twice on one line. (A deliberately fake token value was used for that test; no real
token was written anywhere to produce it.) NGF's data plane runs `error_log stderr info;`, so
`[error]` lines are emitted and land on the same disk by the same path as the access log.

So a **failing** hub connect still writes the token to disk: a 502 during a rolling deploy, an upstream
timeout, a pod killed mid-handshake. Lowering `NginxProxy.logging.errorLevel` past `error` would hide
these lines and would also hide every upstream failure worth seeing — a worse trade, and not taken.
The only real close is moving the token out of the query string, which both `5-14` and this item scope
out on purpose. Left open, named, and handed to whoever picks that design up.

### 4. The other two hosts diverge from the API — but do not leak

Checked, as the scope asked. `Ago.Chat.Worker` and `Ago.Chat.Webhooks` **do not** set
`"Microsoft.AspNetCore": "Warning"`; both `appsettings.json` files carry only `Default: Information`
and `Microsoft.Hosting.Lifetime: Information`. The consequence is real and visible in their pod logs:

```
Request starting HTTP/1.1 GET http://ago-chat-worker.ago-chat.svc.cluster.local:80/metrics - - -
```

That is the exact line the API's setting exists to suppress, and it prints the full URL including any
query string. It is **not** a token leak, because those two hosts map three endpoints between them and
none takes a query string or a token: `/healthz/live`, `/healthz/ready`, `/metrics`
(`Ago.Chat.Worker/Program.cs`, `Ago.Chat.Webhooks/Program.cs`). So this is a consistency gap and log
noise on every scrape, not a finding. Left unchanged here — `ago-chat` was another session's
repository while this ran — and recorded for whoever aligns the three hosts' logging configuration.

### 5. A correction to an assumption `5-14` made in passing

`5-14` reasons that a visitor token is "a smaller blast radius" than an operator one, which is true of
*scope* — a visitor token grants only that visitor's own conversation (`api-design.md`). For a token
written to a **log**, lifetime matters at least as much as scope, and the two run opposite ways:

| | lifetime | where set |
|---|---|---|
| Visitor token | **30 days** — **7 since `17-08`**, see below | `JwtTokenService.VisitorTokenLifetime` |
| Operator access token | **5 minutes** | realm `accessTokenLifespan: 300` (`17-06`, `adr/0034`) |

A logged operator token is stale before anyone could read the file; a logged visitor token stays usable
for a month. So on this specific path the visitor token was the worse of the two, not the milder one —
the opposite of the intuition, and worth stating because the intuition is otherwise correct.

> **Corrected 2026-08-27 (`17-03`).** The thirty days was true when this was written and is not now:
> `17-07`+`17-08`/`adr/0048` shipped visitor-session renewal and moved the lifetime to **seven days**.
> The row is left as it stood with the correction beside it, because the *finding* — that lifetime
> matters at least as much as scope for a credential written to a log, and that the two run opposite
> ways here — is unchanged by the number. Seven days is still three orders of magnitude longer than
> five minutes.

### A methodological trap, recorded because it nearly produced a false "all clear"

The first run of this verification used `@microsoft/signalr` under Node and found **no** query string
in the access log. That result was wrong, and the reason is in the library:
`WebSocketTransport.connect` branches on `Platform.isNode` and sends the token as an
`Authorization: Bearer` **header** on the upgrade in Node, appending `?access_token=` to the URL only
in a browser. A Node SignalR client therefore does not reproduce the request shape this whole item is
about. The verification that counts sent what a browser sends — a raw WebSocket upgrade with the token
in the query string, followed by the real SignalR JSON handshake and a real `JoinAsync` — and the
server accepted it, which is what proves the query-string path is live rather than theoretical.
Anyone re-checking this: confirm your client is producing a browser-shaped request before believing a
negative.

## Context to read first

`docs/backlog/5-14-fix-signalr-logs-access-token-to-console.md` — the client half, and its
"Server-side logging" out-of-scope note, which this item narrows rather than contradicts.
`docs/architecture/edge.md` — what terminates client connections and therefore what logs them; its
"Access logging" section now carries this item's result.
`ago-platform/src/Ago.Platform.Hosting/ServiceCollectionExtensions.cs` — the instrumentation call, and
the fact that a change there is a platform change: `CHANGELOG.md` entry and a version bump, or CI
republishes the old package. (No change was needed — see finding 2.)
`docs/backlog/16-05-personal-data-outside-the-database.md` — the broad sweep of what leaks into logs
and traces; this item is its first concrete target and hands over its method as well as its result.

## Scope

- Make a real hub connection against the deployment and **read the gateway's access log**. Record what
  is there verbatim enough to be conclusive, with the token itself redacted in whatever is written
  down — a backlog item is a public file (`CLAUDE.md`: everything is public). **Done — finding 1.**
- If the token is there: configure the log format to drop or redact the query string. Note the
  interaction with `16-05`, whose own scope includes defining retention for that same log, since it
  also carries client IPs. **Done.** The interaction is now sharper than "note it": the access log
  keeps client IPs and this item deliberately did not touch retention, so `16-05` still owns the
  question of how long these lines live. What changed is that they no longer contain a credential, so
  that retention decision is about personal data alone.
- Make a real hub connection and **inspect the resulting span in Jaeger**. If the query is recorded,
  filter or redact it where the instrumentation is configured, in `Ago.Platform.Hosting` — with the
  CHANGELOG entry and version bump that any public platform change needs. **Done — finding 2, no
  change needed.**
- **Write the result down either way.** "Checked on this date, the token is not there" is the outcome
  worth keeping; without it the next person re-runs the same investigation from the same defaults.
  **Done — that is what finding 2 is.**
- Check whether the `Ago.Chat.Webhooks` and `Ago.Chat.Worker` hosts share the API's logging
  configuration or diverge from it — same one-line question, two more `appsettings.json` files.
  **Done — finding 4. They diverge, and it does not leak.**

## On writing this down publicly

Kept specific on purpose, per `architecture/repositories.md`'s rule: both clients' logging
configuration is in public source, so a vaguer description here would protect nothing and cost a
session the reasoning. The one thing this item must *not* record is a captured token or a log line
containing one — the Scope above says so explicitly for that reason. Every log line quoted here has
its token replaced, the only IP addresses are the cluster's own internal ones, and the error-log
demonstration was produced with a fake token value on purpose so that no real one was ever written in
order to be photographed.

## Out of scope

- The browser-client fix — `5-14`, and it should land whenever it lands; neither item blocks the other.
- Moving the token out of the query string — ruled out by both items, for the same reason. Finding 3
  is the strongest argument yet in favour of reopening that, and is written down as such.
- The broad logs-and-traces audit — `16-05`. This item chases one known value to a definite answer;
  that one sweeps for everything else.
- Access-log retention as a policy — `16-05` again. This item changed the log's *format*; how long
  the log is kept is that item's question.
- Aligning `Ago.Chat.Worker`/`Ago.Chat.Webhooks` logging with the API's (finding 4) — a one-line
  `appsettings.json` change in each, in a repository this item did not have.

## Done when

- [x] The gateway access log has been read after a real hub connection, and the result recorded with a
      date — with the log format fixed if the token was there. **The token was there; the format is
      fixed in both overlays and re-verified live.**
- [x] A real hub-connect span has been inspected in Jaeger, and the result recorded — with the
      instrumentation fixed, versioned and changelogged if the token was there. **It was not there;
      OpenTelemetry redacts query values by default, so no platform change, no version bump.**
- [x] The other two hosts' logging configuration has been checked against the API's. **They diverge;
      the divergence is real but carries no token, since neither host serves an endpoint that takes a
      query string.**
- [x] `5-14`'s "not implicated" note points here for the server-side half, so the two items do not
      contradict each other.
- [x] `16-05` references this item's findings rather than re-deriving them.

## Open questions

One, and it is finding 3's: nginx's error log carries the query string and cannot be configured not
to. Everything else has a definite answer above.
