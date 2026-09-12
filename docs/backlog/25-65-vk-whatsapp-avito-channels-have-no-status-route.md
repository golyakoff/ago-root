# 25-65 · VK, WhatsApp and Avito channels have no status route at all

- **Stage**: 25
- **Status**: ready
- **Verified**: 2026-09-12 — confirmed in `ago-chat/src/Ago.Chat.Api/Channels/`: `VkChannelEndpoints.cs`,
  `WhatsAppChannelEndpoints.cs` and `AvitoChannelEndpoints.cs` each map only `POST ""`
  (`HandleConnectAsync`) and `DELETE "/{channelCredentialId:guid}"` (`HandleDisconnectAsync`) — no
  `MapGet` at all. `TelegramChannelEndpoints.cs` (the pattern the other three should follow) maps
  `GET ""` → `HandleStatusAsync` first. `Ago.Chat.Application.UseCases.GetChannelCredentialStatus.
  GetChannelCredentialStatusHandler` is real and already channel-neutral — the missing piece per
  channel is only the endpoint wiring, not new business logic.
- **Depends on**: nothing
- **Found**: 2026-09-12, while building `25-15`'s VK console connection screen — the console-side
  worker adapted around the gap (no status load on mount, connection state kept in memory for the
  page visit only) rather than working around it with a client-side guess, and named it as a real
  remaining gap rather than silently assuming coverage.

## What is actually true

Telegram and MAX both answer `GET /api/v1/console/channels/{kind}` with a real connection status
(`HandleStatusAsync`, backed by the shared `GetChannelCredentialStatusHandler`). VK, WhatsApp and Avito
each only accept `POST` (connect) and `DELETE` (disconnect) — there is no way for a console screen, or
any other caller, to ask "is this channel currently connected" for any of the three without inferring
it from the result of a connect attempt. `25-15`'s own `VkChannelPage` had to be built without a status
check on mount as a direct consequence — a real, visible product gap (a page reload loses the
"connected" view entirely, even though the credential is still live server-side), not a hypothetical
one.

## Scope

- Add a `GET ""` route to `VkChannelEndpoints.cs`, `WhatsAppChannelEndpoints.cs` and
  `AvitoChannelEndpoints.cs`, each delegating to `GetChannelCredentialStatusHandler` the identical way
  `TelegramChannelEndpoints.HandleStatusAsync`/`MaxChannelEndpoints`'s own status handler already do —
  read both as the template, since `25-15`'s own investigation found MAX's own status route already
  close to a direct match for this shape.
- Once the route exists, `25-15`'s own `VkChannelPage` (and any future WhatsApp/Avito screen) should
  read it on mount the same way `TelegramChannelPage`/`MaxChannelPage` do, replacing the current
  "connect form always shows, connected state lives only in memory for the page visit" workaround.

## Where this is likely to go wrong

- **This is additive wiring, not new domain logic.** `GetChannelCredentialStatusHandler` is already
  channel-neutral; resist the temptation to special-case anything per channel inside it — if VK,
  WhatsApp or Avito genuinely need a different status shape (e.g. VK's own live `groups.getById` check
  the connect flow already does), that is worth naming explicitly rather than assumed away.
- **The console-side follow-up (wiring `VkChannelPage` to read the new route) is real work, not a
  trivial addition** — don't fold it silently into this item's own Done-when as a one-line afterthought
  if it turns out to need real state-management changes to the page.

## Done when

- [ ] `VkChannelEndpoints`, `WhatsAppChannelEndpoints` and `AvitoChannelEndpoints` each answer a
      `GET` status route, matching `TelegramChannelEndpoints`/`MaxChannelEndpoints`'s own shape.
- [ ] `VkChannelPage` (`ago-console`) reads the new route on mount and shows the real persisted
      connection state after a reload, replacing the current in-memory-only workaround.
