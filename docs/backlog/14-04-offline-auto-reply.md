# AGO Inbox: offline auto-reply (scripted, v1)

- **Stage**: 14
- **Status**: done (`adr/0066`)
- **Was**: ready — scoped to the scripted keyword variant only; the LLM-backed variant is named
  below as a real, deliberately deferred option, not this item's job
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md` — channel-agnostic by design,
  so it does not additionally depend on `14-02`/`14-03` shipping first, only on the concept those items
  also build against

## Goal

When no operator is available, a visitor gets an automatic reply instead of silence — on the widget
itself and on any connected channel (`14-02`'s MAX, `14-03`'s SMS, and whichever of `14-05`'s channels
eventually ship) alike, since the reply mechanism is deliberately built at the level `SendVisitorMessage`'s
own pipeline already unifies every channel into, not per-channel. Off by default, tenant-toggleable —
this is a real, named product capability, not a silent behaviour change to existing tenants' widgets.

## Context to read first

`docs/vision.md`'s corrected "Explicitly out of scope" list (this stage's own doc-consistency fix,
made in the same change that added this stage) — "bots/LLM auto-replies" is no longer blanket out of
scope; this item is exactly the capability that correction exists for, scoped to the scripted variant.
`docs/architecture/authorization.md`'s RBAC model — the new tenant-level toggle needs a permission
gating who can turn it on (`site:configure`, the same permission `5-08`'s admin role already holds for
this class of setting — reuse it, do not invent a new one for a single boolean). `docs/architecture/
caching.md` — the toggle's own value belongs in `Site`'s existing config, read the same cache-aside way
`GetSiteConfigByPublicKeyHandler` already reads every other per-site setting, not a new mechanism.

## Scope

- `Site` gains an `OfflineAutoReplyEnabled` flag (default `false`) and a small set of keyword→response
  scripted rules, configurable per site — the exact rule shape (simple keyword match vs. a small
  decision tree) is an implementation detail this item decides and states, not a genuine open product
  question; keep it deliberately simple, matching the product spec's own "cheap, predictable, no
  external dependency" framing for the v1 variant.
- A check at the point a visitor's message would otherwise wait for an operator (the existing "no
  operator assigned → waiting queue" path, `vision.md`'s own core-scenario 3): if
  `OfflineAutoReplyEnabled` and no operator is online for the site, send the matched scripted reply
  through the same outbound path the visitor's channel already uses (widget hub push, or `14-01`'s
  own outbound side for a channel conversation) — one mechanism, every channel, per this item's own
  Goal.
- Console surface (a small addition to whatever site-settings screen `5-08`'s admin role already
  reaches) to toggle the flag and edit the keyword rules.
- **The LLM-backed variant is explicitly named as a real, later option, not built here**: state
  plainly, in this item's own scope note, that a real LLM-backed conversational reply is a genuine
  per-message external-API cost and a different pricing/tier category from the flat scripted version —
  `CLAUDE.md`'s rule against inventing a "typical production" number applies directly to any specific
  model/provider/per-token price, so this item names the LLM variant as future work with an explicit
  open question (below) rather than picking a provider speculatively.

## Out of scope

- The LLM-backed auto-reply variant — named above, a real future item once the cost/provider question
  has a real answer, not this item's job.
- Per-channel customization of the scripted reply (a different message on SMS vs. the widget) — nothing
  in the product spec asks for this; the same reply text works everywhere in v1.
- Unattended booking triggered from an auto-reply — `21-01`, a separate, genuinely unsolved capability.

## Done when

- [x] `Ago.Chat.Application.Tests`: a message arriving with no operator online and the flag enabled
      triggers the scripted reply; the same message with the flag disabled does not.
      `SendOfflineAutoReplyHandlerTests`, plus the two conditions the item did not name and
      `adr/0066` had to decide - an *online* operator suppresses the reply even when every one of them
      is busy, and a conversation somebody has already picked up is never replied to.
- [x] Verified live against at least one real channel - the widget's own protocol, end to end through
      real Postgres, RabbitMQ and Redis (`OfflineAutoReplyDeliveryEndToEndTests`): a visitor's message
      goes through `SendVisitorMessageHandler`, the outbox, `OutboxDispatcher`,
      `OfflineAutoReplyConsumer`, the reply's own outbox row, `ConnectionFanoutConsumer` and
      `NodeDeliveryConsumer`, and arrives at the visitor's own connection as the exact
      `MessageReceived` frame the widget parses. **Not** verified in a browser against a deployed
      cluster - see "Not verified" below.
- [x] Console toggle proven end to end: `OfflineAutoReplyEndToEndTests.EnablingTheToggle_...` writes
      through the console's own handler and then waits for the *cached* per-site read to reflect it,
      over the real outbox -> RabbitMQ -> cache-invalidation chain. That test also caught the reason
      it would not otherwise have worked: `SiteCacheInvalidationConsumer` had only ever evicted one of
      this row's two cache keys (`caching.md`).
- [x] `docs/vision.md`'s corrected out-of-scope note now says exactly what shipped and what did not.
      The roadmap entry is deliberately left to the managing session - `docs/roadmap.md` collides on
      every concurrent item.

## What was decided here that the item did not name

- **"No operator is available" is three conditions, and this fires on two of them** - nobody online,
  and nothing assigned. An online-but-full operator is a queue wait, not an absence (`adr/0066`).
- **The loop guard is structural, not a runtime check**: the reply is authored
  `MessageAuthorKind.System` by the only method that can create one, and the consumer acts on
  `Visitor` alone. Proven by removing it and watching a reply trigger a reply against a real broker.
- **Idempotency is `adr/0017`'s inbox ledger** - the reply, its outbox row and the dedup row commit in
  one `SaveChangesAsync`, so a redelivered trigger persists nothing at all.
- **The rule shape** is a required fallback plus an ordered, first-match-wins keyword list; substring,
  ordinal, case-insensitive; no regex, no decision tree.
- **A real bug the work surfaced**: a validating value object behind a cached DTO must be a record
  *class*, not a `readonly record struct` - `System.Text.Json` will not use a struct's parameterised
  constructor, so every rule came back with null fields on a cache *hit* (never on a miss).
  `SiteConfigCacheRoundTripTests` is the guard that now exists for the whole cached shape.

## Not verified

- **A browser against a deployed cluster.** Nothing here was deployed (that is the managing session's
  call), so "an offline visitor sees a labelled bubble in a real page" rests on the delivery test above
  plus `ago-widget`'s own DOM test, not on someone watching it happen.
- **Cost under load.** Every visitor message now costs one extra consumer hop on every site, including
  the majority with the feature off. The skip path does one cached config read and no database work at
  all, but no number is attached to that - Stage 7's load test is where it would get one.

## Open questions

**Whether/when to build the LLM-backed variant, and which provider/pricing tier it would need** —
genuinely open, not decided here. `CLAUDE.md`'s rule against inventing numbers applies; a future item
should name a real provider and a real, cited per-token/per-message cost (the same research discipline
`adr/0026` applied to VPS hosting) before committing to build it, not before naming it as a real
roadmap possibility.
