# 26-319 · [channels] a MAX bot with no public username yields a dead chat link, shown as "all good"

- **Stage**: 26
- **Status**: ready — not yet verified · carries a small product/UX call
- **Found**: 2026-09-30, onboarding the first real client «Салон Топаз». The MAX channel link opened
  `https://max.ru/@id663313676809_bot` and MAX answered «Не нашли чат по этой ссылке». The token was
  valid, the bot registered, and the console showed the channel as healthy.

## Root cause (verified live)

`ChannelLinkUrlBuilder` builds `https://max.ru/@{handle}` (25-148), where `handle` is the bot's public
`@username` read from MAX's `GET /me` (25-147, stored as `channel_credentials.public_handle`). For Топаз
the stored MAX handle is **`id663313676809_bot`** — the default handle MAX assigns a bot that has **no
custom public username**. `max.ru/@id<user_id>_bot` is not a resolvable public chat, so MAX shows
"chat not found". (Contrast Telegram, whose handle is a real username `ago_chat_topaz_dress_bot` because
BotFather requires one; MAX does not.)

So the token check is right that the token works — but "valid token" and "the public link resolves" are
two different facts, and today only the first is surfaced. The operator gets a healthy-looking channel
and a dead link, with nothing telling them a username must be set in MAX.

## Fix

Treat "no public username" as a first-class, surfaced channel state for MAX:
- Detect the MAX default-handle shape (`^id\d+_bot$`) — that value is not a real username — when the
  token check / channel status runs, and mark the channel as **linkable=false / "username not set"**
  rather than healthy.
- Surface it in the console channel status (and anywhere the chat link is offered): a clear notice —
  "MAX bot has no public username; the chat link won't work. Set a username in MAX, then reconnect" —
  instead of emitting a broken `max.ru/@id..._bot` link. Consider suppressing the MAX entry from the
  visitor handshake `channelLinks` (25-148) while the handle is a default id-handle, so a visitor is
  never handed a dead link.
- Product call: whether to hard-block connecting a MAX bot with no username, or connect-but-warn.
  Recommended: **connect-but-warn** (the inbound bot still works via long-polling; only the public link
  is affected), with the warning prominent until a real username is read.

## Done when

- [ ] A MAX bot whose `/me` returns an `id<digits>_bot` default handle is shown in the console as
      "username not set / link unavailable", not healthy, and no `max.ru/@id..._bot` link is offered.
- [ ] After the owner sets a username in MAX and reconnects, the real handle is stored and the link works.
- [ ] The visitor handshake never hands out a dead MAX link.
- [ ] Product decision (hard-block vs connect-but-warn) recorded here.
