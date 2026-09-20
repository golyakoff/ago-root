# 25-176 · A WhatsApp channel's status screen never actually asks WhatsApp anything

- **Stage**: 25
- **Status**: done — `ago-chat#345` (`d920b96`). Independently re-verified by the managing session before
  merging: diff reviewed line-by-line, and the full `ago-chat` command set re-run directly — `dotnet
  format`/`build` clean, all 6 non-empty test assemblies green, 3823/3823 tests (one interim run hit an
  unrelated Testcontainers Docker port-bind race in `SchemaMigratorTests`; confirmed as a transient
  environment flake, not a regression, by re-running that file alone clean and then the full suite clean
  end to end).
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

- [x] A WhatsApp status read with a good token reports `Verified: true` and the current
      `display_phone_number`. — `WhatsAppChannelStatusLiveCheckTests.GetWhatsAppStatus_WithAGoodToken_ReportsVerifiedAndBackfillsTheChangedDisplayNumber`.
- [x] A WhatsApp status read with a revoked/bad token reports `Verified: false` with a stated reason. —
      `...WithARevokedToken_ReportsVerifiedFalseWithAStatedReason`.
- [x] A WhatsApp status read when Meta's API (or this deployment's egress) is unreachable reports
      `Unreachable: true`, distinct from a refusal. — `...WhenWhatsAppIsUnreachable_ReportsUnreachable_DistinctFromARefusal`.
- [x] `PublicHandle` updates on a status read when the number's own display format has changed since
      connect time. — covered by the same good-token test above (asserts the backfill).
- [x] `dotnet build`/`format`/`test` green for `ago-chat`. — re-run independently, 3823/3823 tests, 0
      failed. `ago-console` needed no change — checked fresh, there is no `WhatsAppChannelPage.tsx` at
      all yet (WhatsApp is still behind the "Другие каналы" placeholder), so there is no existing page
      whose status shape could go stale.
