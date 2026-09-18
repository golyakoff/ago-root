# 25-148 · The visitor handshake carries no channel links

- **Stage**: 25
- **Status**: done — `ago-chat#328`
- **Found**: 2026-09-18, scoping the author's own request. The widget has no way to learn which
  messaging channels a site has connected, or what to link to for any of them.
- **Depends on**: `25-147` (a channel's own public handle has to exist before it can be exposed).
  Touches `ago-chat` only.

## Scope

- New read port `IPublicChannelLinkReadStore` (`Ago.Chat.Application/Abstractions`), one method
  returning `(ChannelKind Kind, string Handle)` per connected, handle-bearing channel for a site -
  modelled on `IEnabledModuleReadStore`, implemented as a Dapper read in `Infrastructure.Postgres`
  alongside the other `*ReadStore.cs` files. **A read store, not a fifth method on
  `IChannelCredentialRepository`, deliberately**: that repository's own `GetActive`/`GetById` return
  the whole aggregate, `TokenCiphertext` included - a read store that projects only `kind` and
  `public_handle` cannot leak a token, because it never loads one. State this reasoning in the PR, per
  this project's teaching-mode convention - it is a real dependency-rule-flavoured choice, not a
  style preference.
- One new additive field on `AuthEndpoints.VisitorSessionResponse`, on **both** the mint and the renew
  path - the identical shape `25-131` already used for `EnabledModuleTriggerWords`:
  ```
  "channelLinks": [
    { "kind": "Telegram", "url": "https://t.me/example_shop_bot" },
    { "kind": "Max",      "url": "https://max.ru/@example_shop_bot" }
  ]
  ```
  `kind` is `ChannelKind`'s own CLR member name (PascalCase, matching `WidgetPosition`/`WidgetLocale`'s
  convention on this same response). `url` is an absolute `https` URL, **built server-side** - never
  a bare handle the widget would have to template into a provider-specific URL itself. This is the
  load-bearing shape decision: a server-built URL means a new channel lights up with zero widget code
  changes (only its icon needs a later cosmetic addition); sending `{kind, handle}` would put provider
  vocabulary (`t.me/`, `max.ru/@`) in the widget and require a widget change per channel. Write this
  decision up as its own ADR - it is exactly the "a guarantee/shape a reviewer would expect to see
  argued" case `adr-writer` exists for.
- Read live, through the new read store - **not** via the 5-minute `GetSiteConfigByPublicKeyHandler`
  cache, the same reasoning `EnabledModules` already established: a tenant who just connected a
  channel wants it to show up now, and a credential write does not raise the cache-eviction event a
  widget config change does.
- A site with nothing connected gets `channelLinks: []`, never `null` or an absent field.
- **The author's own explicit decision, 2026-09-18: bundle the Telegram identity-continuity mechanism
  into this same item, not deferred.** Read `docs/backlog/14-12-*.md` and `adr/0079` in full before
  scoping this half - `PendingChannelLinkRequestOptions`'s own remarks already describe this exact
  scenario ("long enough for a visitor to switch to another app, find the shop's bot, and send one
  message"), and a 15-minute linking-code mechanism already exists for a visitor typing
  `/linkidentity telegram <code>` by hand. What this item adds: Telegram's own `url` in `channelLinks`
  carries `?start=<code>` (a freshly-minted linking code, generated per visitor session the same way
  `/linkidentity`'s own code already is), and the Telegram inbound handler recognises a `/start
  <code>` message - the format Telegram itself sends when a user opens a `t.me/bot?start=X` link - as
  equivalent to the existing `/linkidentity telegram <code>` flow, not a new, parallel mechanism.
  **Investigate the existing code-generation/verification path first** (is it a callable use case
  already, or logic embedded in the inbound-message handler that needs extracting into one?) and
  reuse it rather than building a second one. If `/start`'s own payload format turns out to need
  something the existing mechanism does not provide (e.g. a code mintable without the visitor typing
  a command first), say so plainly and scope that gap explicitly rather than working around it
  silently.

## Where this is likely to go wrong

- **Never let `channelLinks` carry anything from `ChannelCredential` beyond `kind` and the built URL**
  - no `ChannelCredentialId`, no `ProviderAccountId`, no token-shaped field of any kind. Extend
  `ChannelPortTests`'s existing `Token|Secret`-forbidding check (or add a sibling test) to cover this
  new type explicitly - do not rely on it being "obviously fine."
- **MAX and VK do not get a `?start=` code in this item** - only Telegram's own inbound handler is
  being taught to recognise one. Do not build a generic "every channel gets a linking code" mechanism
  speculatively; scope precisely to what Telegram's own `/start` payload actually needs.
- If a visitor's linking code expires before they tap the link (the same 15-minute window
  `PendingChannelLinkRequestOptions` already bounds), the Telegram side should fail exactly the way
  `/linkidentity`'s own expired-code path already does today - not a new, second failure mode.

## Done when

- [x] `VisitorSessionResponse` carries `ChannelLinks`, additively, on both the mint and renew paths;
      every existing field and consumer is unchanged
- [x] A site with nothing connected gets `channelLinks: []`
- [x] Read live, proven not to come from the cached `SiteConfigDto`
- [x] A new or extended arch test proves the new type carries no token/secret/credential-id-shaped
      property
- [x] An ADR records the server-built-URL decision and the read-store-not-repository choice
- [x] Telegram's own `url` carries a fresh linking code; opening it and sending the bot's own default
      `/start` reply continues the same conversation the widget already had - proven live, not only
      against a test double
- [x] An expired or already-used code fails the identical way `/linkidentity`'s own existing failure
      path already does

## Outcome

`IPublicChannelLinkReadStore` (Dapper, deliberately not a fifth `IChannelCredentialRepository`
method - that repository's reads carry `TokenCiphertext`). `ChannelLinkUrlBuilder` builds the full
`https://` URL server-side. `MintVisitorChannelLinkCodeHandler` mints Telegram's `?start=<code>` as
a third, symmetric originator of `PendingChannelLinkRequest` alongside `14-12`'s two existing ones;
degrades to a plain link when a visitor session has no persisted `Visitor` row yet. Proven against
real Postgres/real handlers in `TelegramLinkContinuityTests` (headline continuity + expired-code
fallthrough) - the test's own doc comment is explicit that this is the maximum provable without a
real Telegram bot token and deployed webhook, the same honesty this codebase already states for
VK/MAX. `ADR-0175` records the two shape decisions. Full suite green (same counts as `25-147`).
`ago-chat#328`.
