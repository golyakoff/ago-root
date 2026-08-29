# AGO Inbox: VK (ВКонтакте) channel adapter

- **Stage**: 14
- **Status**: built (2026-08-29, `ago-chat#124`, not yet merged) — a
  real message reaches an operator and a real console reply reaches VK back, both proven against a real
  Postgres and the real production handler/endpoint chain; **not yet verified against a real VK
  community and a real account** — no VK access token exists in the environment this item was built in.
  See "What was and wasn't verified" below before checking the remaining Done-when boxes.
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md` — reuses the port and
  `ChannelIdentity` concept unchanged, the same way `14-02` (MAX) and `14-07` (Telegram) already do

## Goal

A visitor can message a shop's AGO Chat operators through a VK community's own messages (Сообщения
сообщества), and get a real operator reply back through the same channel — the third concrete channel
adapter after MAX (`14-02`) and Telegram (`14-07`).

## Why this, and why now

`ago-business/docs/decisions/0009-razryv-po-fucham-s-jivo-chto-stroim-chto-net.md` names VK as a real,
qualitatively weighty gap against the nearest direct competitor (Jivo), specifically for the target
customer this project already committed to (`0002`: a small Russian online shop) — Russian social
commerce runs heavily through VK, arguably more than through Telegram for this exact segment, though
that is a qualitative argument in the business decision, not a number measured here. This item exists
because the business side named it, not because an engineering session picked it independently — read
`0009` before touching scope here if the business reasoning needs revisiting.

## Context to read first

`14-02`'s own backlog file and its "Tenant routing and credential ownership" section — the identical
question (which tenant does an inbound message belong to, one-bot-per-tenant vs platform-wide-bot vs
AGO-registers-on-tenant's-behalf) needs answering again for VK's own API shape, which may differ from
MAX's (VK's Callback API for community messages uses a community access token plus a confirmation
string, not quite the same bot-registration flow — verify against VK's own current documentation before
assuming MAX's answer transfers unchanged). `docs/architecture/resilience.md`'s outbound-webhook
treatment, reused unchanged through `14-01`'s port, exactly as `14-02`/`14-07` already do.

## Confirmed against VK's own documentation, 2026-08-29

`dev.vk.com` was unreachable from this environment (the same kind of network restriction `14-02`'s own
report notes for MAX), so this item's source of truth is VK's own official open-source SDK
(github.com/VKCOM/vk-php-sdk, generated from VK's own published API JSON Schema), fetched via its raw
GitHub source, not a third party's write-up. This is firmer ground than `14-02`'s own reconstruction had
- MAX's shapes came from third-party integration write-ups because no official source was reachable
either.

- **Base URL `https://api.vk.com/method`, version pinned via a `v` parameter (`5.199`, this SDK's own
  current default), the access token travels as an ordinary `access_token` POST parameter** - not a
  header (MAX) or a URL-path segment (Telegram). A genuine third shape, not a repeat of either precedent.
- **VK's REST convention answers both success and failure with HTTP 200** - the outcome lives in the JSON
  body (`{"response": ...}` or `{"error": {"error_code": N, "error_msg": "..."}}`), confirmed from the
  SDK's own response-parsing code, which never branches on the HTTP status at all. `VkApiClient` reads
  the body regardless of status for this reason - the one thing neither MAX's nor Telegram's own outbound
  client had to do.
- **The Callback API confirmation handshake** - confirmed from the SDK's own server-handler base classes:
  a `{"type": "confirmation", "group_id": ..., "secret": ...}` event, answered with the raw confirmation
  string as the *entire plain-text response body* (no JSON), and every other event answered with the
  literal text `"ok"`, not an empty 200. Both are proven by `VkWebhookEndpointsTests` against the real
  route.
- **`messages.send` needs a `group_id` alongside the community's own access token** - VK's own SDK lists
  it as a legitimate parameter "for group messages with group access token". Rather than guess whether
  it is strictly required, this item always sends it, discovered once via `groups.getById` at connect
  time and stored on `ChannelCredential.ProviderAccountId` (a new, nullable, additive column - MAX's and
  Telegram's own rows never populate it). This is the one piece of state neither MAX nor Telegram needed.
- **VK also publishes `groups.getCallbackConfirmationCode`** - a live API call that returns the exact
  string a community's own Callback API settings page expects back, given the community's token and id.
  This item calls it live, inside the webhook handler, rather than asking the shop to copy the code out
  of VK's own UI into this system - removing a manual step MAX's/Telegram's own flows never needed either
  (neither has an equivalent value to copy).
- **A community's own outgoing messages loop back through the same `message_new` event as inbound
  ones**, distinguished only by `message.out` (`0` inbound, `1` outgoing) - a shape with no MAX/Telegram
  equivalent. Missing this would have created a reply loop the first time an operator answered through
  this channel; `VkInboundMessageParser` filters `out == 1`, proven by a dedicated test at both the
  parser level and through the real webhook route.
- **VK's own numeric error-code taxonomy for `messages.send`**, confirmed from the SDK's own
  `error_code -> exception` table: `5`/`7`/`15` (auth/permission/access) and the messages-specific
  refusals `900`/`901`/`902`/`917`/`932` are treated as terminal refusals; everything else (including
  `6`/`9`/`29`, rate limiting and flood control) defaults to transient and is retried by the same
  resilience pipeline every other channel uses.

## Tenant routing and credential ownership — decided 2026-08-29, before merge

The identical question `14-02`'s own file answers for MAX: **one VK community access token per tenant**,
the shop's own, entered once and never shown back (`adr/0069`'s shape, reused unchanged). VK's own
constraints confirm this transfers cleanly rather than needing a different answer: a community access
token is inherently scoped to one community (there is no platform-wide VK bot concept the way a single
Telegram bot could in principle serve many chats), and AGO registering a community on a tenant's behalf
is not possible any more than it was for MAX or Telegram - VK requires the community's own admin to
create the token. The one genuinely new wrinkle is `ProviderAccountId` (above): VK's shape needs a second,
non-secret identifier alongside the token, which MAX's and Telegram's own self-addressing bot tokens
never did.

**VK's own inbound mechanism is webhook-only in this item's own scope, closer to MAX's webhook half than
to Telegram's poll-only design, and unlike MAX's own dual webhook+poll shape, VK ships with no
polling-loop fallback here.** VK's Callback API is push, exactly as this item's own Scope section
predicted. VK does publish a second, structurally unrelated mechanism ("Bots Long Poll API",
`groups.getLongPollServer` plus its own polling loop) that could have served MAX's own "dev-only
fallback" role - but it is a materially different API surface (its own provisioning call, its own event
envelope, its own server/key/ts bookkeeping), not a toggle on the client this item already built. Building
it would have been a second full adapter for one channel; this item scoped it out as a named gap rather
than building it silently or pretending VK offers no alternative at all. `VkChannelAdapter`'s own remarks
carry the same note in code.

## Scope

- A `ChannelKind.Vk` value (or equivalent — confirm the current `ChannelKind` enum's exact shape before
  assuming a bare addition is enough) and a concrete `IInboundChannelAdapter` implementation for VK's
  Callback API.
- Inbound: VK's Callback API delivers events via an HTTP callback to a URL a community admin configures
  — this is push, not poll, a different shape from MAX's/Telegram's own inbound mechanism; the exact
  webhook verification/confirmation handshake VK requires needs its own spike before assuming the
  existing `IInboundChannelAdapter` shape fits without change.
- Outbound: reply delivery via VK's own Messages API, wrapped in the same resilience pipeline every
  other channel already uses.
- Tenant routing and credential ownership, decided explicitly before code, the same way `14-02` did.
- Console-facing connect/disconnect endpoints, matching `TelegramChannelEndpoints.cs`'s/
  `MaxChannelEndpoints.cs`'s own shape.

## Out of scope

- VK Ads/marketing API, VK Donut, or anything beyond a community's own direct messages.
- Group posts/comments — only direct messages to the community, the same channel shape every other
  adapter in this stage covers.

## Done when

- [ ] A real message sent to a real VK community's messages reaches an operator through the same
      console queue a widget conversation already does. **Not verified live** — proven instead against
      the real production handler chain (`VkWebhookEndpointsTests`, real Postgres, real Kestrel host on
      the real `MapVkWebhookEndpoints` route, a realistic `message_new` fixture built from VK's own SDK
      source plus one third-party captured-payload write-up for the part the SDK source does not cover -
      `VkDtos.cs`'s own honesty note). What remains unverified is whether VK's real Callback API delivery
      reaches this route over the public internet, and whether the `object.message` nesting this item
      assumed is VK's true shape.
- [ ] A console reply reaches the same VK conversation back — **not verified live**, same reason. Proven
      instead against a real HTTP boundary (`VkApiClientTests`, `VkChannelAdapterTests`): a real message
      is sent, VK's own terminal/transient error-code split is honoured, and the outbound `random_id` is
      derived deterministically so a resilience-pipeline retry cannot double-post.
- [x] Tenant routing and credential ownership are decided and recorded, the same way `14-02`'s own
      backlog file records its equivalent decision — see "Tenant routing and credential ownership" above.

**No VK community access token exists in the environment this item was built in** - the same honest gap
`13-02`'s own ЮKassa signature verification left open, named plainly rather than claimed solved. Closing
both remaining boxes needs a real VK community, a real callback URL VK can reach (this deployment's own
public domain, matching `MaxChannelEndpoints`' equivalent requirement), and a real account to message
from - the same live-verification pass `14-02`/`14-07` each report finding real bugs during, which this
item's own honesty note says plainly it could not run.

## Open questions

None new - the webhook-vs-poll question this item's own Scope section named is resolved (see "Tenant
routing and credential ownership" above): webhook-only, no VK-side polling fallback built. The one
open item is the live-verification pass itself, tracked as the two unchecked Done-when boxes above, not
a design question.
