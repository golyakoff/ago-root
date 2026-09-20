# 25-175 · A VK channel's status screen never actually asks VK anything

- **Stage**: 25
- **Status**: ready — the live-call tradeoff below is decided by the author, 2026-09-20: yes, build it.
- **Depends on**: nothing (independent of `25-174`/`25-176`/`25-177` - different provider, different
  files, no shared code path beyond the two both mirror, `TelegramLiveTokenCheck`)
- **Found**: 2026-09-20, alongside `25-174` - `VkChannelEndpoints.cs`'s own doc comment names this exact
  gap, dated `25-65`: *"VK's public API has no side-effect-free equivalent of Telegram's own `getMe`
  that this endpoint could call on every status read without mutating anything or racing another
  caller... for a live-check richness this item was never asked to add."*

## What is actually true today, and the one correction to that 25-65 note

`VkChannelEndpoints.HandleStatusAsync` reports only whether an active credential row exists - it never
calls VK. `groups.getById` (`VkApiClient.GetGroupInfoAsync`) is called exactly once, at connect time, to
validate the token and discover the community's numeric id.

**Re-reading `25-65`'s own comment carefully: `groups.getById` is not actually unsafe to repeat** - it
is a plain read, the same "no side effect" character `VkApiClient.GetGroupInfoAsync`'s own doc comment
draws to `TelegramChannelEndpoints.GetMeAsync`. The real, and only, reason `25-65` left this out was
scope and cost - calling it on every screen view means every screen view makes a live VK call on the
tenant's behalf, and `25-65` was never asked to add that richness. That is the same tradeoff Telegram
already accepts for itself; this item is the author's decision to accept it for VK too, made explicitly
rather than assumed.

**Unlike MAX or Telegram, there is no `PublicHandle` to backfill here.** `VkChannelEndpoints.
HandleConnectAsync`'s own comment: VK's public link (`vk.me/club<id>`) is fully derivable from
`ProviderAccountId` alone, computed at read time by `PublicChannelLinkReadStore` - storing a second,
redundant handle would only invite drift. So this item is pure status-richness (`Verified`/`Refused`/
`Unreachable`), never a backfill - the smallest of the three real gaps found today.

## Scope

- A `VkLiveTokenCheck`, mirroring `TelegramLiveTokenCheck`'s own three-outcome shape - wrapping
  `VkApiClient.GetGroupInfoAsync`, called with the credential's own stored token.
- `VkChannelEndpoints.HandleStatusAsync` calls it on every read. **No `PublicHandle` write anywhere in
  this item** - see above; do not add one VK was explicitly designed not to need.
- `VkChannelStatusResponse` gains `Verified`/`Unreachable`/`RefusalReason`/`CheckedAt`, matching
  whatever shape `25-174` settles on for `MaxChannelStatusResponse` (check that item's own outcome
  before inventing a third shape).
- Reuse a 5-second timeout constant, the same reasoning `TelegramLiveTokenCheck.Timeout`/`25-174`'s own
  `MaxLiveTokenCheck.Timeout` state for themselves.

## Out of scope

- Any `PublicHandle` mechanism for VK - deliberately absent, per `25-147`'s own decision, unchanged here.
- MAX, WhatsApp, Avito's own equivalent gaps - `25-174`, `25-176`, `25-177`.

## Done when

- [ ] A VK status read with a good token reports `Verified: true`.
- [ ] A VK status read with a revoked/bad token reports `Verified: false` with `groups.getById`'s own
      stated error reason.
- [ ] A VK status read when VK (or this deployment's egress) is unreachable reports `Unreachable: true`,
      distinct from a refusal.
- [ ] No `PublicHandle` write is introduced anywhere in this change.
- [ ] `dotnet build`/`format`/`test` green for `ago-chat`; `ago-console` only if `VkChannelPage` needed a
      change (check the existing generic problem-details rendering first, per `25-174`'s own note).
