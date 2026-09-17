# 25-116 · The Telegram relay never protected the API's own `getMe` call

- **Stage**: 25
- **Depends on**: nothing (closes a gap `14-07`/`adr/0070` named and deliberately deferred)
- **Status**: ready — fix written, not yet applied live or verified.
- **Found**: 2026-09-16, the author connecting a real Telegram bot through the new channel-entitlement
  UI (`25-115`): the "Подключить" button stayed on "Подключаем..." indefinitely.

## What is actually true today

`14-07`/`adr/0070` measured this VPS's own outbound path to `api.telegram.org` and found it fails
outright roughly half the time (DPI-style interference specific to Telegram's own domains, not a
general outage - a control host answered every time in the same window). The fix built then was a
SOCKS5 relay (Xray-core, tunnelling through the author's own personal VLESS endpoint) running as an
init-container sidecar inside `ago-chat-worker`'s own pod, reachable only at `127.0.0.1` - because a
sidecar shares its parent pod's network namespace, and only `Ago.Chat.Worker` was in scope for that
item (its own long-polling and reply-delivery paths).

That patch's own comment already named the gap this item closes, in the same change that introduced
it: `Ago.Chat.Api`'s `RegisterChannelCredentialHandler` also calls Telegram - a live `getMe` token
check, made synchronously the moment a tenant clicks "Подключить" - and that call got no proxy at all,
left exposed to the identical failure rate. It was left as a named, deliberate gap rather than fixed,
with two remedies already named: duplicate the sidecar into `Ago.Chat.Api`'s own pod, or expose the
relay as a real Service with a NetworkPolicy.

**Re-measured 2026-09-16, worse than the original finding**: 10 of 10 direct connections to
`api.telegram.org` from this VPS timed out (10s, zero TCP handshake each time) - `telegram.org` itself
timed out identically, `api.github.com` from the same node answered in 150ms. Whether this is the same
intermittent interference having gotten more consistent, or a harder block now in place, was not
determined further - the fix (route around it) is identical either way.

## Fix

Promoted the relay from an `ago-chat-worker`-only sidecar to a standalone `telegram-relay` Deployment +
ClusterIP Service (`k8s/overlays/demo/telegram-relay.yaml`), reachable from both `ago-chat-api` and
`ago-chat-worker` via `Channels__Telegram__Proxy__Socks5Address=telegram-relay:1080`, gated by a new
`telegram-relay-ingress` NetworkPolicy (`network-policies.yaml`) allowing only those two hosts.
`TELEGRAM_RELAY_XRAY_CONFIG`'s own `listen` field moved from `127.0.0.1` to `0.0.0.0` on the node (a
loopback bind cannot be reached through a Service - only a real Pod-IP-reachable bind can), updated
directly in the gitignored `.env.telegram-relay` file, never committed. One relay instance, one VLESS
connection, instead of two independent copies - `adr/0070`'s own "personal endpoint, not AGO-owned
infrastructure, no SLA" gap is a reason to minimise how many connections lean on it, not multiply them.

The old sidecar's own readiness-probe limitation (documented at length in the patch it replaced -
kubelet always probes the Pod IP, so a loopback-bound listener could never pass a `tcpSocket` probe)
is resolved as a side effect: the relay now genuinely is Pod-IP-reachable, so a `tcpSocket: 1080`
readiness probe was added rather than left absent.

## Where this is likely to go wrong

- **The real `.env.telegram-relay` file on the node needs its own `listen` field changed by hand** -
  this repository never sees that file's real contents (gitignored, holds the personal VLESS UUID).
  Applying this change without also updating that file leaves the relay listening on `127.0.0.1`
  inside a Service that can never reach it, which looks like a routing problem rather than a config one.
- **Two hosts sharing one relay means one relay outage now affects both**, not just message delivery -
  `adr/0070`'s own "if the relay is down, Telegram is down for every tenant using it" consequence now
  also covers the connect flow. Unchanged in kind, widened in scope; still the accepted trade the ADR
  already made.

## Done when

- [ ] `Ago.Chat.Api`'s own outbound Telegram calls (`getMe`, credential registration) route through the
      same relay `Ago.Chat.Worker` already used.
- [ ] A real end-to-end walk: connect a real Telegram bot token through the console.
- [ ] The old sidecar-only shape is fully removed, not left running alongside the new Service.
