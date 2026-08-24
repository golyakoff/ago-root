# Does the hub token reach the edge access log, or the traces?

- **Stage**: 17
- **Status**: ready
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

## What is unverified — the actual subject

- **The edge access log.** `ago-deploy` contains no access-log configuration of any kind: no log
  format, no snippet, nothing in `k8s/overlays/demo/gateway.yaml`. NGINX Gateway Fabric's defaults
  therefore apply, and NGINX's default combined format logs the full request line, query string
  included. If that holds here, every hub connection on the public deployment writes a valid bearer
  token to a log on disk.
- **The trace spans.** `Ago.Platform.Hosting`'s `AddAspNetCoreInstrumentation()` is called with no
  filter and no enrichment. Current OpenTelemetry semantic conventions record the request's query on
  server spans, so the hub-connect span may be carrying the token into Jaeger.

Both are stated as things to go and check. Neither is asserted — the defaults make each plausible,
and a plausible leak is not a finding until somebody has looked.

## Context to read first

`docs/backlog/5-14-fix-signalr-logs-access-token-to-console.md` — the client half, and its
"Server-side logging" out-of-scope note, which this item narrows rather than contradicts.
`docs/architecture/edge.md` — what terminates client connections and therefore what logs them.
`ago-platform/src/Ago.Platform.Hosting/ServiceCollectionExtensions.cs` — the instrumentation call, and
the fact that a change there is a platform change: `CHANGELOG.md` entry and a version bump, or CI
republishes the old package. `docs/backlog/16-05-personal-data-outside-the-database.md` — the broad
sweep of what leaks into logs and traces; this item is its first concrete target and hands over its
method as well as its result.

## Scope

- Make a real hub connection against the deployment and **read the gateway's access log**. Record what
  is there verbatim enough to be conclusive, with the token itself redacted in whatever is written
  down — a backlog item is a public file (`CLAUDE.md`: everything is public).
- If the token is there: configure the log format to drop or redact the query string. Note the
  interaction with `16-05`, whose own scope includes defining retention for that same log, since it
  also carries client IPs.
- Make a real hub connection and **inspect the resulting span in Jaeger**. If the query is recorded,
  filter or redact it where the instrumentation is configured, in `Ago.Platform.Hosting` — with the
  CHANGELOG entry and version bump that any public platform change needs.
- **Write the result down either way.** "Checked on this date, the token is not there" is the outcome
  worth keeping; without it the next person re-runs the same investigation from the same defaults.
- Check whether the `Ago.Chat.Webhooks` and `Ago.Chat.Worker` hosts share the API's logging
  configuration or diverge from it — same one-line question, two more `appsettings.json` files.

## Out of scope

- The browser-client fix — `5-14`, and it should land whenever it lands; neither item blocks the other.
- Moving the token out of the query string — ruled out by both items, for the same reason.
- The broad logs-and-traces audit — `16-05`. This item chases one known value to a definite answer;
  that one sweeps for everything else.
- Access-log retention as a policy — `16-05` again. This item may change the log's *format*; how long
  the log is kept is that item's question.

## Done when

- [ ] The gateway access log has been read after a real hub connection, and the result recorded with a
      date — with the log format fixed if the token was there.
- [ ] A real hub-connect span has been inspected in Jaeger, and the result recorded — with the
      instrumentation fixed, versioned and changelogged if the token was there.
- [ ] The other two hosts' logging configuration has been checked against the API's.
- [ ] `5-14`'s "not implicated" note points here for the server-side half, so the two items do not
      contradict each other.
- [ ] `16-05` references this item's findings rather than re-deriving them.

## Open questions

None. Both questions have a definite answer; the item is the work of going and getting it.
