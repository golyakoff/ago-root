# ADR-0070: Telegram outbound calls routed through a VLESS relay

- **Status**: Accepted
- **Date**: 2026-08-28
- **Stage**: 14

## Context

`docs/backlog/14-05-telegram-whatsapp-spike.md` blocked any Telegram adapter code on a real, measured
reachability spike from the same Russian-hosted VPS `adr/0026` deploys to — MAX (`14-02`) and SMS
(`14-03`) carry no such open question, Telegram does, because Telegram's own API has a documented
history of intermittent interference from Russian networks and nobody had measured this deployment's
own path to it.

## Decision

Measured 2026-08-28, from the live VPS (`<node-ip>`), direct: 15 requests to `https://api.telegram.org`
(a deliberately invalid bot token — the point is TCP/TLS/HTTP reachability, not authenticated
functionality; an HTTP 401 proves a complete round trip), spaced 20 seconds apart over a 6-minute
window, 10-second timeout per attempt.

- **7 of 15 (47%) succeeded**, averaging **132ms** round-trip.
- **8 of 15 (53%) hit the full 10-second timeout with zero TCP connection ever established**
  (`time_connect = 0.000000`) — not a slow response, a connection that never completed at all.
- **Control**: 5 of 5 requests to `https://www.google.com` from the same VPS in the same window all
  succeeded (121–402ms) — ruling out general network flakiness on this VPS. The failure is specific to
  `api.telegram.org`, consistent with intermittent DPI-level interference on the outbound path rather
  than a hard IP block (a hard block would show 0/15, not 7/15).

**Re-measured through a relay, same day.** The author already runs a personal VLESS endpoint
(`golyakov.net:443`, TLS) for unrelated purposes. Routing the identical request through it (a local
Xray-core client on the VPS, exposing a `127.0.0.1` SOCKS5 proxy) and repeating the same 15-request
spike (5s apart, same 10s timeout): **15 of 15 (100%) succeeded**, averaging **~210ms** (the added tunnel
hop over the ~132ms direct-when-working figure). One real defect surfaced and fixed along the way:
the relay endpoint's own TLS server was serving only its leaf certificate, not the full chain, which
independently broke validation regardless of the Telegram question — fixed via the 3x-ui panel
re-issuing the certificate, confirmed with `openssl s_client -showcerts` (1 certificate before, 4 after,
`Verify return code: 0` after).

**Decision: build the Telegram channel adapter (`14-07`), with its outbound HTTP calls routed through
this relay.** The interference is specific to the outbound path from this VPS to Telegram's own
infrastructure — a relay that egresses from a different network entirely sidesteps it completely, and
the measurement above is real evidence it works, not an assumption.

## Consequences

- `Ago.Chat`'s Telegram adapter needs a proxy-aware outbound `HttpClient` (or equivalent) — a genuinely
  new shape versus MAX's direct-connection adapter, since MAX needed no such workaround. Scoped in
  `docs/backlog/14-07-telegram-channel-adapter.md`.
- **A relay dependency is now load-bearing for one channel.** If the relay is down, Telegram is down for
  every tenant using it — a different failure mode than "occasionally slow," and worth its own
  monitoring rather than assuming the existing circuit-breaker pattern covers it silently.
- **The relay is the author's own personal VLESS endpoint, not AGO-owned infrastructure.** This is a
  known, accepted gap for a portfolio/demo deployment — no SLA, and the author's own service ToS for
  commercial/server-side use has not been separately reviewed here. Worth revisiting before any real
  paying tenant depends on Telegram specifically (`ago-business`'s own commercial-intent framing).
- **Inbound webhook reachability from Telegram's servers to this VPS was not measured** — only the
  outbound direction (this VPS calling Telegram) was tested and fixed. `14-07` should treat long-polling
  as Telegram's primary production mechanism for this reason, not merely a local-dev convenience the
  way `14-02` treated MAX's poller — an inbound webhook would introduce a second, unmeasured
  reachability question the relay does not address at all (the relay is this VPS's own egress; it does
  nothing for Telegram's servers reaching in).
- No secret from this relay (the VLESS UUID) is ever written to any repository — it is deployment
  configuration, held as a Kubernetes Secret exactly like `14-02`'s channel credentials, never in a
  manifest or committed `.env` (`repositories.md`'s "no secrets, ever").

## Alternatives considered

- **Defer Telegram, revisit later.** The direct-connection-only conclusion this ADR held for a few hours
  the same day. Superseded once the relay was actually tried and measured rather than assumed — `defer`
  was correct given only the first measurement, not once a real fix existed.
- **Build the adapter now, rely on `Ago.Platform.Resilience`'s existing retry/circuit-breaker policies to
  absorb the direct-connection failure rate.** Rejected: those policies handle a slow or
  occasionally-erroring dependency, not one where roughly half of all attempts return nothing at all
  within a generous 10s window — routing around the interference is a better fix than tuning retries
  against it.
- **Provision new, AGO-owned relay infrastructure instead of the author's personal VLESS endpoint.**
  Not rejected, deferred: more correct for a real commercial deployment, but the personal endpoint is
  what proved the approach works today at zero incremental cost, and swapping the relay later is a
  configuration change (a different SOCKS5 address), not a redesign.
