# 25-178 · The console never shows a MAX channel's live verification state

- **Stage**: 25
- **Status**: done — `ago-console#261` (`ade7d09`). Independently re-verified by the managing session
  before merging: diff reviewed (direct structural port of `TelegramChannelPage`'s badge logic, new
  MAX-specific i18n strings, no shared strings), all four commands re-run directly — `typecheck`/`lint`
  clean, 1533/1533 unit tests, 67 passed/9 skipped `ux-gate`.
- **Depends on**: `25-174` (the API now returns `Verified`/`Unreachable`/`RefusalReason`/`CheckedAt` -
  this item only surfaces what already exists on the wire)
- **Found**: 2026-09-20, by the worker landing `25-174` - flagged in its own report rather than built as
  a side effect: `MaxChannelPage.tsx`'s own doc comment argued, from the premise `25-174` corrected, that
  MAX deliberately shows no verification badge. That premise is now stale.

## What is actually true today

`ago-chat`'s MAX status route (`25-174`) reports `Verified`/`Unreachable`/`RefusalReason`/`CheckedAt` on
every read, the same shape `TelegramChannelEndpoints`'s own route has always returned. `ago-console`'s
`maxChannelApi.ts` declares `MaxChannelStatusDto` as a strict three-field TypeScript interface
(`connected`/`channelCredentialId`/`createdAt`) - the extra JSON fields arrive on the wire and are simply
ignored, silently, by the type. `MaxChannelPage.tsx` renders no verification badge at all -
`TelegramChannelPage.tsx` is the direct precedent for what this screen should do instead: an unreachable
badge, a verified/unverified badge, and a refusal reason shown as an alert when unverified
(`TelegramChannelPage.tsx` lines ~185-216 are the exact logic to mirror).

## Scope

- Widen `MaxChannelStatusDto` to the same four extra fields `TelegramChannelStatusDto` already carries.
- `MaxChannelPage.tsx` renders the same three-state badge (`unreachable` / `verified` / `unverified with
  reason`) `TelegramChannelPage.tsx` already does - reuse that component's own strings/`Alert` pattern
  rather than inventing new copy; add MAX-specific i18n strings mirroring the Telegram ones
  (`telegramChannelVerifiedBadge` etc.) rather than reusing Telegram's own strings for a different
  channel's screen.

## Out of scope

- VK/WhatsApp/Avito's own console screens - each has its own sibling backlog item for the API half
  (`25-175`/`25-176`/`25-177`); this item is MAX's console half only. A console item for each of those,
  once its own API item lands, is a reasonable follow-up but not decided or filed here.
- Any change to the API response shape itself - `25-174` already shipped it.

## Done when

- [x] `MaxChannelStatusDto` carries `verified`/`unreachable`/`refusalReason`/`checkedAt`. — widened in
      `src/api/maxChannelApi.ts`, matching `TelegramChannelStatusDto`'s field names/types verbatim.
- [x] `MaxChannelPage` shows an unreachable badge when the API reports one, a verified badge when
      verified, and an unverified badge with the stated reason otherwise. — `MaxChannelPage.test.tsx`'s
      `connectedAndVerified`/`connectedButRefused`/`connectedButUnreachable` cases, each with negative
      assertions confirming the other two states' text never leaks in.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` all green for `ago-console`. — re-run independently:
      typecheck/lint clean, 1533/1533 tests (141 files), `ux-gate` 67 passed/9 skipped (expected,
      viewport-gated specs), 0 failed.
