# AGO Inbox: MAX channel adapter

- **Stage**: 14
- **Status**: ready
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md`

## Goal

A real visitor can message a shop's AGO Chat operators through MAX (VK's own Russian-market messenger,
a free, open Bot API) and get a real operator reply back through the same channel — the first concrete
implementation of `14-01`'s port, and the proof it is shaped correctly. Chosen to be built first among
every channel this product plans to support, for the reason the product spec states plainly: no known
regulatory or legal friction, and a documented Bot API with no reliability question needing a spike
first, unlike Telegram/WhatsApp (`14-05`).

## Context to read first

`docs/architecture/resilience.md`'s "Outbound webhooks to a shop's CRM" row and the whole "How this is
proven" section — this item's own outbound calls to MAX's Bot API (sending a reply) are a boundary with
exactly the same shape (someone else's HTTP API, can be slow or down, must not be allowed to degrade
the rest of the system), so the same timeout/retry/circuit-breaker treatment applies, wrapped through
`14-01`'s own port rather than a bespoke mechanism for this one channel. `14-01`'s own Scope section —
this item is its first real caller, and any gap found in the port's own shape while building this
adapter belongs in a note on this item, not a silent workaround.

## Scope

- `MaxChannelAdapter` (`Ago.Chat.Infrastructure.MaxBot`, one project per external technology matching
  `naming-and-structure.md`'s existing "one project per external technology" rule): implements
  `IInboundChannelAdapter` for MAX's Bot API — inbound message receipt (MAX's own webhook or long-poll
  mechanism, whichever its API actually offers; state which once confirmed against MAX's real
  documentation, not assumed) and outbound reply sending, both wrapped in `Ago.Platform.Resilience`'s
  existing policies via the same `ResiliencePipeline` shape `Ago.Platform.Storage.S3` already
  establishes for a real external HTTP dependency.
- A bot registered with MAX for local/dev testing — credentials sourced from `infra-credentials`/
  `docker/.env`, never committed (`repositories.md`'s "no secrets, ever," unchanged).
- The webhook endpoint (if MAX's API is webhook-shaped) or the polling `BackgroundService` (if long-poll)
  lives in `Ago.Chat.Api`/`Worker` respectively, following whichever of the two matches
  `adr/0013`'s own failure-profile reasoning — a webhook receiver is request-shaped (`Api`), a poller is
  restart-tolerant background work (`Worker`); state which MAX's actual API requires and place it there
  accordingly, not by default.

## Out of scope

- SMS, Telegram, WhatsApp — `14-03`/`14-05`.
- Offline auto-reply's own interaction with this channel — `14-03`'s own scope covers making auto-reply
  channel-agnostic; this item only has to prove a real operator reply reaches MAX correctly.
- Unattended booking through MAX — `21-01`, blocked, genuinely unsolved UX question.

## Done when

- [ ] A real message sent from a real MAX account reaches an operator in the console, through the same
      queue a widget conversation already uses (`14-01`'s own mapping into `SendVisitorMessage`) —
      verified live against a real MAX bot, not a fake adapter.
- [ ] A real operator reply from the console is delivered back to the same MAX conversation — verified
      live, both directions proven, matching this repository's own "verified means actually run"
      standard (`k8s-local.md`'s own phrase, applied here).
- [ ] `Ago.Chat.Integration.Tests` (or a MAX-specific fixture matching `AttachmentFixture`/`MinioFixture`'s
      own precedent for a real-external-dependency test harness): MAX's outbound API stopped/unreachable
      degrades gracefully (the circuit breaker opens, the rest of the system's message pipeline is
      unaffected) — proven with a real container-failure-style test, not asserted.
- [ ] `docs/architecture/resilience.md` gains MAX's Bot API as a named row (or note) in the boundary
      table, and `docs/architecture/data-model.md`/`messaging.md` get whatever schema/event notes this
      adapter's real implementation surfaces.

## Open questions

None — MAX is named in the product spec as the deliberately lowest-friction channel to build first
specifically because it has no open legal/reliability question the way Telegram/WhatsApp do; anything
this item finds genuinely uncertain about MAX's own API belongs as a note on this item once discovered,
not a pre-emptive open question here.
