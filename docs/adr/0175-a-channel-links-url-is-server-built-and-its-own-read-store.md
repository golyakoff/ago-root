# ADR-0175: A visitor-facing channel link is a server-built URL, read through its own store

- **Status**: Accepted
- **Date**: 2026-09-18
- **Stage**: 25
- **Item**: `25-148` (the visitor handshake carries no channel links), on top of `25-147` (a connected
  channel never records its own public address)
- **Relates to**: `adr/0069` (channel credential shape), `adr/0079` (verified channel-identity linking),
  `20-07`'s `IEnabledModuleReadStore` (the read-store precedent this item's own store is modelled on)

## Context

The widget has no way to learn which messaging channels a site has connected, or what to link to for
any of them - the author's own Jivo-style "message us on Telegram/MAX/..." switcher has nothing to
switch to. `25-147` made the raw fact (a channel's own public handle) available on `ChannelCredential`;
this item puts it on the wire, on `AuthEndpoints.VisitorSessionResponse`, the same additive-field shape
`25-131`'s `EnabledModuleTriggerWords` already used on this response.

Two decisions could not be defaulted silently:

1. What exactly does the widget receive for each connected channel - a handle it must interpret itself,
   or something it can act on directly?
2. Where does the read that produces this live - is it a new method on the existing write-side
   repository, or something else?

## Decision 1 - the wire carries a full, server-built URL, never a bare handle

**`channelLinks` is `[{ kind, url }]`, where `url` is an absolute `https://` address built entirely on
the server** (`https://t.me/<username>`, `https://max.ru/@<username>`, `https://wa.me/<digits>`,
`https://vk.me/club<id>`) - never `{ kind, handle }` left for the widget to template into a
provider-specific URL itself.

The alternative - sending the bare handle and letting `ago-widget` know that Telegram means `t.me/` and
MAX means `max.ru/@` - is the one most codebases reach for, because it looks like less server code. It
was rejected because it puts provider vocabulary in the wrong repository: `ago-widget` would need a
release, coordinated with `ago-chat`, every time a new channel with a public deep link is added, and
the widget would carry a small but real per-channel URL-formatting table with no way to test it against
this codebase's own arch tests (`ChannelPortTests.NoProviderVocabulary_AppearsAboveInfrastructure`
already refuses that vocabulary above Infrastructure in *this* repository - the same discipline simply
does not reach across a repository boundary). With a server-built URL, a future channel with a public
deep link needs one new arm in `ChannelLinkUrlBuilder.BuildUrl` and zero widget code changes; only a
later, purely cosmetic icon addition is left for the widget to do at all.

`ChannelLinkUrlBuilder` lives in `Ago.Chat.Application`, not `Ago.Chat.Domain` - deliberately not beside
its nearest sibling, `ChannelEntitlementOptionKeys` (Domain). That type's own remarks draw the line this
decision turns on: its `"channel-" + kind` naming is a fact this codebase invented and could reasonably
never let a deployment override. A provider's own public deep-link format is the opposite kind of fact
- external, owned by Telegram/MAX/VK themselves - so it is treated the way this codebase already treats
provider-owned facts generally (kept out of Domain), while staying out of Infrastructure too, since it
needs no HTTP client, no provider SDK, and its only two collaborators
(`IPublicChannelLinkReadStore`, `MintVisitorChannelLinkCodeHandler`) already live in Application.

## Decision 2 - a new read store, not a fifth method on `IChannelCredentialRepository`

**`IPublicChannelLinkReadStore.GetForSiteAsync` is a new port in `Ago.Chat.Application/Abstractions`,
implemented as a Dapper read (`PublicChannelLinkReadStore`) in `Infrastructure.Postgres` - modelled
directly on `IEnabledModuleReadStore`'s own shape, not a new method on `IChannelCredentialRepository`.**

`IChannelCredentialRepository`'s existing methods (`GetActiveAsync`, `GetByIdAsync`, ...) return the
whole `ChannelCredential` aggregate, `TokenCiphertext` included - the shop's own bot token, still
encrypted, but a value nothing on a visitor-facing handshake path (reachable by anyone who knows a
site's public key) has any business loading into memory at all. A read store that projects only `kind`
and a handle column cannot leak a token, structurally, because it never selects one - the identical
"cannot leak what it never loaded" guarantee `IEnabledModuleReadStore`'s own narrower projection already
gives module credentials on the sibling handshake field beside this one.

This also settles `25-147`'s own open question about VK: **VK's handle is derived at read time, from
the already-stored `ProviderAccountId`, and never stored on `ChannelCredential.PublicHandle` at all.**
`PublicChannelLinkReadStore`'s own SQL computes it with a `coalesce`/`case` over `kind = 'Vk'`, in the
one place a VK row is ever turned into a link. Storing a second, redundant column was rejected: nothing
about a VK link can ever change independently of `ProviderAccountId`, so a second column would only
invite the two to drift, for no read this store cannot already answer directly.

Read live, through this store, never through the 5-minute `GetSiteConfigByPublicKeyHandler` cache the
rest of `VisitorSessionResponse` is built from - the identical reasoning `EnabledModules`/
`EnabledModuleTriggerWords` already established on this same response: a tenant who just connected a
channel wants it to show up on the very next handshake, and a credential write raises no cache-eviction
event the way a widget config change does.

## Consequences

- A visitor-facing response now carries a URL a stranger with a site's public key can request - the
  arch-test guard (`ChannelPortTests.ChannelLinkResponse_CarriesNoTokenSecretCredentialOrAccountIdProperty`)
  is what keeps that response from ever widening into something that leaks a credential-shaped fact,
  the same discipline `MaxChannelResponses_CarryNoTokenOrSecretProperty` already holds the
  operator-facing connect/status responses to.
- A second `ChannelKind`-keyed table now exists (`ChannelEntitlementOptionKeys` in Domain,
  `ChannelLinkUrlBuilder` in Application) answering two different, easily-confused questions - "which
  billing option" versus "which URL" - for the same enum. Anyone extending one when they meant the other
  will not be caught by the compiler; only this ADR and each type's own remarks record why they are not
  one table.
- Telegram's own row additionally triggers a write (`MintVisitorChannelLinkCodeHandler`) on an otherwise
  read-only handshake path - a genuinely new kind of side effect for `AuthEndpoints` to have, and the one
  this item found could not always be satisfied (a freshly-minted visitor session has no persisted
  `Visitor` row yet, so the pending-link-request's own foreign key cannot be written): handled as a
  graceful `null` - a plain Telegram link with no continuity code - rather than a failed handshake.

## Alternatives considered

- **`{ kind, handle }` on the wire, formatted by `ago-widget`** - rejected in Decision 1: couples a
  widget release to every new channel with a public deep link, and puts provider vocabulary in a
  repository this codebase's own arch tests cannot reach.
- **A fifth method on `IChannelCredentialRepository`** - rejected in Decision 2: that repository's
  return type already carries a token; a projection-shaped read has no way to ride along on it without
  either widening the aggregate's own read path or adding a second, narrower load method that duplicates
  most of what a read store already is, for no benefit over building the read store directly.
- **Storing VK's derived handle on `ChannelCredential.PublicHandle` at connect time** (`25-147`'s own
  open question, settled here) - rejected: a second column that can only ever equal a formula over a
  column already on the same row is pure redundancy, and redundant state is state that can drift.
