# 26-319 · [channels] the MAX chat link had a spurious `@` and did not resolve

- **Stage**: 26
- **Status**: done — merged as `ago-chat#404` (`d136dea`), deployed to the stand and pinned.
- **Found**: 2026-09-30, onboarding the first real client «Салон Топаз». The MAX channel link opened
  `https://max.ru/@id663313676809_bot` and MAX answered «Не нашли чат по этой ссылке». Token valid,
  bot registered, console healthy.

## Root cause (corrected — the first diagnosis was wrong)

My initial read was "the bot has no public username". **That was wrong** — the author confirmed the bot's
username in MAX *is* `id663313676809_bot` (MAX assigns that `id<user_id>_bot` handle by default and it
cannot be changed), and we already read it correctly from `GET /me` via the token — nothing needs to be
typed at connect time.

The real cause: `ChannelLinkUrlBuilder` built the MAX link as **`https://max.ru/@{handle}`** — with a
leading `@`. MAX's own bot deep link is **`https://max.ru/<botName>`** with **no `@`**
(dev.max.ru/docs/chatbots/bots-coding/prepare: `https://max.ru/<botName>?start=<payload>`; profiles use
`max.ru/u/...`, channels `max.ru/<name>`). The `@` was a `25-148` design-time assumption (that MAX
mirrored a mis-remembered Telegram `@` form), never verified against real MAX. So every MAX link was
`max.ru/@...` and did not resolve.

Telegram was unaffected — its handle is a real username and `t.me/<username>` was already correct.

## Fix

`ChannelKind.Max => $"https://max.ru/{handle}"` (drop the `@`) in `ChannelLinkUrlBuilder`, with the test
updated to assert `id663313676809_bot` resolves to `https://max.ru/id663313676809_bot`. One backend
change fixes every consumer (the visitor-handshake `channelLinks` and the console) at once. Deployed on
ago-chat `d136dea`.

## Done when

- [x] MAX links are `https://max.ru/<handle>` with no `@`; test asserts the id-handle case.
- [x] Deployed to the stand; `https://max.ru/id663313676809_bot` opens the bot.
- [x] No client change needed (backend builds the URL, widget/console just render it).
