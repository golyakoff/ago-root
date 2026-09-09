# 25-09 · Five of six channels have an adapter and no console screen

- **Status**: ready
- **Date found**: 2026-09-09, closing `23-36`'s own "Open questions" note against what actually
  shipped
- **Depends on**: `23-36` (built and merged) named the shape; none of the underlying adapters
  (`14-02` MAX, `14-08` VK, `14-09` Email, `14-10` WhatsApp, `14-11` Avito) block this — they already
  ship.

## What `23-36`'s own open question turned into

`23-36` asked *"six channels, one screen or six?"* and named the real differences between them
(Email is RFC-direct with no vendor, WhatsApp goes through Meta's own onboarding, Avito is an account
rather than a bot) as the reason one generic screen would be wrong in four places. What actually
shipped answers a narrower question than the one asked: **`ago-console` has exactly one channel
screen, `TelegramChannelPage`.** MAX, VK, Email, WhatsApp and Avito each have a working backend
adapter and no way for a tenant to connect one without the API.

That is the same gap `23-36`'s own "What is actually true today" section described for all six before
it shipped — now true for five. `TelegramChannelPage` is the shape to follow, not to generalise from
by guessing: it is one worked answer to "one screen or six" (one, per channel, its own file), not
proof that the other five look the same underneath.

## Scope

Whichever of the five channels comes first gets a screen following `TelegramChannelPage`'s own
discipline (`23-36`'s own text, restated here since it still applies):

- The token is never echoed back — shown once at entry, never re-rendered.
- "Connected" means the provider agreed, verified live at entry and on every later read.
- Disconnect unlinks, it does not delete.
- What the tenant sees for a channel that stopped working at the provider's end.

## Where this is likely to go wrong

- **Each channel really is a different shape**, per `23-36`'s own finding. Building a second screen by
  copying `TelegramChannelPage`'s file and swapping labels risks smuggling Telegram's own bot-token
  assumption into a channel that authenticates completely differently (Meta's WhatsApp onboarding,
  Avito's account-based connection). Read the actual adapter each channel already has before assuming
  its console shape.
- **Prioritise by what a tenant would actually ask for first**, not by adapter age. This item does not
  decide which of the five goes first — that is a product call for whoever picks this up.

## Done when

- [ ] At least one more channel (of MAX, VK, Email, WhatsApp, Avito) has a console connection screen,
      following `TelegramChannelPage`'s discipline stated above.
- [ ] Which channel, and why it went first, is stated rather than assumed.
