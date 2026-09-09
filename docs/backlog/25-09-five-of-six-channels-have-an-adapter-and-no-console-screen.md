# 25-09 · Five of six channels have an adapter and no console screen

- **Status**: done — MAX built (`ago-chat#242`, `ago-console#180`); VK, Email, WhatsApp, Avito remain
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

- [x] MAX has a console connection screen (`ago-chat#242`, `ago-console#180`), following
      `TelegramChannelPage`'s discipline — token never echoed back, disconnect unlinks not deletes,
      "connected" verified wherever the provider's own API makes that honest.
- [x] Why MAX went first: its request shape matched Telegram's most closely, and `23-31`'s own nav
      comment had already reserved "Бот MAX" as its own named place, distinct from the generic
      "Другие каналы" catch-all — real signal, not a guess. The one premise that did not hold
      (a status check as cheap as Telegram's `getMe`) is named explicitly in `MaxChannelPage`'s own
      doc comment rather than faked: MAX's connected badge is a single state, never Telegram's
      three-way live check, because MAX's API has no side-effect-free equivalent to check with.
