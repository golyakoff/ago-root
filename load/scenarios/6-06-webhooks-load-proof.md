# Scenario: hung-webhook isolation (6-06)

**Question this answers**: with every registered webhook endpoint hung for 30s on every call, does
chat message send→ack / send→delivered-cross-node latency get measurably worse? Does the per-endpoint
circuit breaker open and stay open (not stuck half-open, not hammering the dead endpoint)? Does the
per-tenant bulkhead's concurrency cap actually get hit and hold?

Full write-up with real numbers: `load/reports/2026-08-23-webhooks-load-proof.md`. This file states
the scenario's shape and how to reproduce it; the report has the results.

## Tool

Not k6 - a real `Microsoft.AspNetCore.SignalR.Client` driver (`ago-chat`'s
`tests/Ago.Chat.LoadDriver`), for the reasons stated in the report's "Deviations" section (k6
unavailable in-session; SignalR's binary hub-protocol framing is a poor fit for a hand-rolled k6 WS
script). This is `6-06`'s own deviation, not a new project-wide convention - `load-test`'s own skill
still names k6 as the default for any future scenario that doesn't have this scenario's specific
constraints.

## Topology (reproduce locally)

`ago-chat`'s compose fast loop (`docs/runbooks/local-dev.md`) plus, from `ago-chat`'s own repo root:

```bash
# infra already up per local-dev.md; migrations applied; demo site seeded
# operator role needs conversation:close granted once (seed script does not grant it by default):
docker exec <postgres-container> psql -U ago -d ago_chat -c \
  "UPDATE roles SET permissions = array_append(permissions, 'conversation:close') WHERE name = 'Operator';"
docker exec <postgres-container> psql -U ago -d ago_chat -c \
  "UPDATE operators SET capacity = 50 WHERE id = '00000000-0000-0000-0000-000000000002';"

export AGO_CHAT_CONNECTION_STRING="Host=localhost;Port=5432;Database=ago_chat;Username=ago;Password=ago-local-dev"
export ASPNETCORE_ENVIRONMENT=Development
export Auth__SigningKey="<any fixed base64 32-byte value, shared by both Api instances>"

ASPNETCORE_URLS=http://localhost:5009 dotnet run --project src/Ago.Chat.Api -c Release --no-launch-profile &   # operator node
ASPNETCORE_URLS=http://localhost:5010 dotnet run --project src/Ago.Chat.Api -c Release --no-launch-profile &   # visitor node
dotnet run --project src/Ago.Chat.Worker -c Release --no-launch-profile &

# register the endpoint once (real product row, bypassing the HTTP API's own SSRF/https-only check
# deliberately - see the report's "Deviations" section for why):
dotnet run --project tests/Ago.Chat.WebhookDispatchRunner -c Release --no-launch-profile -- --seed http://localhost:5290/webhooks/deliver

# at hung_start_utc (printed by the load driver below):
ASPNETCORE_URLS=http://localhost:5290 FakeCrm__DefaultBehavior=hang-30s \
  dotnet run --project tests/Ago.Chat.FakeCrm -c Release --no-launch-profile &
ASPNETCORE_URLS=http://localhost:5292 dotnet run --project tests/Ago.Chat.WebhookDispatchRunner -c Release --no-launch-profile &

LOADDRIVER_LANES=8 LOADDRIVER_BASELINE_SECONDS=60 LOADDRIVER_HUNG_SECONDS=180 \
  LOADDRIVER_SEND_INTERVAL_MS=6500 LOADDRIVER_RECYCLE_SECONDS=45 LOADDRIVER_BULKHEAD_BURST=25 \
  dotnet run --project tests/Ago.Chat.LoadDriver -c Release --no-launch-profile
```

Optional, Windows-only resource sampling alongside the run: `load/lib/resource-monitor.ps1`.

## Load shape

60s baseline (no webhook process running at all) → 180s hung-CRM window (dispatch runner + hung
`Ago.Chat.FakeCrm` live, one registered endpoint) → a 25-conversation concurrent burst fired at the
instant the hung-CRM window opens, meant to stress the per-tenant bulkhead (see the report for why
this needs a fresh, unopened breaker to have any chance of working, and why even that was not
enough).

## Success criteria, chosen before running

- Send→ack and send→delivered-cross-node p50/p95/p99 in the hung-CRM window are not measurably worse
  than the baseline window's own numbers (same hardware, same load shape - the isolation claim, not
  `nfr.md`'s absolute cluster-scale targets).
- At least one real `BreakerOpen`-reasoned dead-lettered delivery, with a real timeout
  (`WebhookResponseHeadersTimeoutException`) preceding it - not merely configured.
- At least one bulkhead-rejection-reasoned dead-lettered delivery, or an honest report of why none
  appeared.
- Api/Worker working-set memory, thread count, and handle count flat across the whole run.
