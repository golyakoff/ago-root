# 25-176 · A WhatsApp channel's status screen never actually asks WhatsApp anything

- **Stage**: 25
- **Status**: ready — the live-call tradeoff below is decided by the author, 2026-09-20: yes, build it.
- **Depends on**: nothing (independent of `25-174`/`25-175`/`25-177`)
- **Found**: 2026-09-20, alongside `25-174`/`25-175` - `WhatsAppChannelEndpoints.cs`'s own doc comment
  names the identical `25-65` gap for this channel too.

## What is actually true today

`WhatsAppChannelEndpoints.HandleStatusAsync` reports only whether an active credential row exists.
`WhatsAppApiClient.GetPhoneNumberAsync(token, phoneNumberId, ...)` - a real, side-effect-free read
(`GET /{version}/{phone-number-id}`) - is called exactly once, at connect time, to validate the token
and fetch `display_phone_number`/`verified_name`. Unlike MAX/Telegram's `getMe` or VK's `groups.getById`
(which self-discover from the token alone), WhatsApp's own token does not disclose which phone number it
means - `phoneNumberId` has to be supplied. It already is: `HandleConnectAsync` stores Meta's own
`phone_number_id` as `ChannelCredential.ProviderAccountId` specifically so later code can call this same
endpoint again - the field exists for exactly this reuse.

## Scope

- A `WhatsAppLiveTokenCheck`, mirroring `TelegramLiveTokenCheck`'s own three-outcome shape - wrapping
  `WhatsAppApiClient.GetPhoneNumberAsync(token, credential.ProviderAccountId, ...)`.
- `WhatsAppChannelEndpoints.HandleStatusAsync` calls it on every read (needs the decrypted token and
  `ProviderAccountId` off the credential row, the same second repository call
  `TelegramChannelEndpoints.HandleStatusAsync` already makes for its own token) and backfills
  `PublicHandle` from `display_phone_number` on a change - the identical `25-147` pattern, since WhatsApp
  already has a real `PublicHandle` (unlike VK).
- `WhatsAppChannelStatusResponse` gains `Verified`/`Unreachable`/`RefusalReason`/`CheckedAt`, matching
  whatever shape `25-174`/`25-175` settle on.
- Reuse a 5-second timeout constant, same reasoning as the other two items.

## Out of scope

- MAX, VK, Avito's own equivalent gaps - `25-174`, `25-175`, `25-177`.
- Any change to how `phoneNumberId` is supplied or validated at connect time.

## Done when

- [ ] A WhatsApp status read with a good token reports `Verified: true` and the current
      `display_phone_number`.
- [ ] A WhatsApp status read with a revoked/bad token reports `Verified: false` with a stated reason.
- [ ] A WhatsApp status read when Meta's API (or this deployment's egress) is unreachable reports
      `Unreachable: true`, distinct from a refusal.
- [ ] `PublicHandle` updates on a status read when the number's own display format has changed since
      connect time.
- [ ] `dotnet build`/`format`/`test` green for `ago-chat`; `ago-console` only if `WhatsAppChannelPage`
      needed a change (check the existing generic problem-details rendering first).
