# AGO Inbox: Telegram channel adapter

- **Stage**: 14
- **Status**: done (2026-08-28) — code merged `ago-chat#106`, deploy merged `ago-deploy#84`/`#85`/`#86`,
  both live-verification Done-when items closed against a real bot (`@ago_chat_demo_bot`); the log-leak
  fix (`ago-chat#107`) is open, not yet merged, tracked separately below
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md` (the port this implements),
  `14-05-telegram-whatsapp-spike.md` (the prerequisite this item was blocked on — now answered for
  Telegram, `adr/0070`)

## Goal

A real visitor can message a shop's AGO Chat operators through Telegram and get a real operator reply
back through the same channel — `14-02`'s MAX adapter, applied to a second channel, plus the one thing
MAX never needed: outbound calls route through a relay, because a direct connection from this
deployment's VPS to Telegram's own API fails outright roughly half the time (`adr/0070`).

## Context to read first

`docs/backlog/14-02-max-channel-adapter.md` in full — this item reuses its shape wherever nothing about
Telegram specifically requires a different answer:
- **Tenant routing and credential ownership**: one bot per tenant, `adr/0069`'s shared
  `ChannelCredential` shape (encrypted column, never shown back, revocation/erasure covered). No new
  decision needed here — Telegram bots are created via `@BotFather`, the same "shop registers its own
  bot, hands AGO the token" model MAX already uses.
- **Resilience wrapping**: `Ago.Platform.Resilience`'s existing timeout/retry/circuit-breaker pipeline,
  same as MAX's `MaxApiClient`.

`docs/adr/0070-telegram-outbound-via-relay.md` — the one genuinely new constraint. Read its Consequences
section before writing any code: the relay is a real dependency (if it's down, Telegram is down for
every tenant on it, a different failure mode than "occasionally slow"), it is the author's own personal
VLESS endpoint (not AGO-owned infrastructure, no SLA), and its credential is deployment configuration
(a Kubernetes Secret), never a repository file.

**Webhook vs. long-polling — decided differently from MAX, and this item must not default to MAX's
answer without re-deriving it.** `14-02` treated its poller as a local-dev convenience and webhook as
the real production mechanism. `adr/0070` only measured and fixed the **outbound** direction (this VPS
calling Telegram); **inbound reachability — Telegram's own servers calling this VPS's webhook — was
never measured and the relay does nothing for it** (the relay is this VPS's own egress, not an ingress
path). Given that, **long-polling is this item's primary production mechanism for Telegram**, not a
dev-only fallback: it only depends on the direction already measured and fixed. A webhook receiver may
still be built if Telegram's own API makes long-polling awkward at scale, but that is new scope this
item should flag rather than assume, and it inherits an unmeasured reachability question this item's
own spike did not close.

## Scope

- `TelegramChannelAdapter` (`Ago.Chat.Infrastructure.Telegram`, one project per external technology,
  matching `naming-and-structure.md` and `14-02`'s own precedent) implementing `IInboundChannelAdapter`:
  inbound message receipt via long-polling (`Worker`, matching `MaxLongPollingService`'s shape) and
  outbound reply sending, both through `Ago.Platform.Resilience`'s existing pipeline.
- **The outbound `HttpClient` (or whichever client sends to `api.telegram.org`) is configured with a
  SOCKS5 proxy** pointed at the relay — a genuinely new piece of DI/`HttpClientFactory` wiring this
  codebase has not needed before (`MaxApiClient`, `AttachmentFixture`'s S3 client, none of the existing
  external clients proxy their traffic). State which layer owns this configuration (a `SocketsHttpHandler.Proxy`
  set at registration time is the standard .NET shape) and why it lives there, per `CLAUDE.md`'s
  teaching-mode requirement — this is new enough to this codebase to be worth explaining rather than
  silently wiring.
- The relay's own address/credential (SOCKS5 endpoint, or the VLESS config if the client runs
  in-process rather than as a sidecar — decide which, see below) sourced from `infra-credentials`/a
  dedicated Secret, never committed.
- A bot registered with Telegram (`@BotFather`) for local/dev testing.

## Deploy shape — new to `ago-deploy`, not just `ago-chat`

This item is not `ago-chat`-only. The relay (an Xray-core VLESS client, proven live 2026-08-28 — see
`adr/0070`) needs to run somewhere reachable by whichever host makes the outbound Telegram calls
(`Ago.Chat.Worker`, per the long-polling decision above). Two shapes, pick one and say why:

1. **Sidecar container** in `Ago.Chat.Worker`'s own pod, sharing its network namespace — the outbound
   client talks to `127.0.0.1:<port>` exactly as tested manually on the VPS. Smallest blast radius: one
   pod's worth of dependency, no new Service, no cluster-wide exposure of an open SOCKS5 proxy.
2. **A separate Deployment + ClusterIP Service** other hosts could also use later (if WhatsApp or
   another channel ever needs the same relay). More reusable, more surface: any pod in the cluster that
   can reach the Service can proxy through it, which is a real question for `17-01`'s tenancy-isolation
   work to have an opinion on before this is chosen over (1).

This deployment repository has **no existing sidecar container anywhere** — if (1) is chosen, that is a
new pattern for `ago-deploy`, worth a line in `docs/architecture/edge.md` or wherever this repository
already documents pod shapes, not just a manifest with no explanation.

The relay's own VLESS UUID is a **deployment secret**, added to `infra-credentials`
(`k8s/overlays/demo/kustomization.yaml`'s existing `secretGenerator`) exactly like every other value
there — never in a committed manifest, never logged. Its own `.env.example` entry should say plainly
what it is and that it is the author's personal endpoint, matching this ADR's own honesty about that.

## Out of scope

- WhatsApp — `14-05`'s legal-review half is still open; unaffected by this item.
- SMS — already unblocked, `14-03`, unrelated.
- A webhook receiver for Telegram — see the long-polling decision above; only in scope if long-polling
  proves genuinely insufficient, and if so, its own inbound-reachability question is new scope, not this
  item's to close.
- Provisioning AGO-owned relay infrastructure to replace the personal endpoint — `adr/0070`'s own
  Alternatives section names this as deferred, not this item's to build.

## Done when

- [x] A real message sent from a real Telegram account reaches an operator in the console, through the
      same queue a widget/MAX conversation already uses — verified live 2026-08-28, through the relay,
      not against a fake adapter (`@ago_chat_demo_bot`).
- [x] A real operator reply from the console is delivered back to the same Telegram conversation —
      verified live 2026-08-28, both directions proven.
- [x] The relay dependency is visible in whatever this repository already uses for boundary
      documentation — `docs/architecture/resilience.md`'s boundary table now carries Telegram's own row,
      naming the relay explicitly, not folded into "same as MAX".
- [x] `ago-deploy` carries the relay (`ago-deploy#84`/`#86`, merged) — a **native sidecar** in
      `ago-chat-worker`'s pod, not a separate Service (the decision this item asked for, made and
      recorded there). Its credential is a **dedicated `telegram-relay-credentials` Secret**, not
      `infra-credentials` as this line originally assumed — six of the eight Deployments reading
      `infra-credentials` do so via blanket `envFrom`, which would have put a personal VLESS UUID in
      Postgres's and MinIO's own environment for no reason; a second Secret confines it to the one
      sidecar that mounts it. A real bug was found and fixed live in the same pass: the sidecar's
      `tcpSocket` readinessProbe could never pass (kubelet probes a container over the Pod IP, never its
      own loopback, and the relay is deliberately loopback-only) — fixed by removing the probe
      (`ago-deploy#86`).
- [x] A test proves the outbound client actually uses the configured proxy (not just that the proxy
      config is set) — `TelegramProxyTraversalTests`, against a real local SOCKS5 listener.

A second gap found live in the same verification pass, fixed separately: the bot token travelled in
full, in plain text, through `Ago.Chat.Worker`'s own logs (`HttpClientFactory`'s default logging redacts
header values but not the request URI, and Telegram's own auth lives in the URL path) — fixed in
`ago-chat#107`, proven with a real captured-log test rather than asserted.

## Open questions

None — `adr/0070` closed the one real prerequisite. The sidecar-vs-Service deploy shape is a decision
this item makes and records, not an open question left for later.
