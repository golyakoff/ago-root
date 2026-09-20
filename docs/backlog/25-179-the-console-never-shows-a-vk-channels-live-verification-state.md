# 25-179 · The console never shows a VK channel's live verification state

- **Stage**: 25
- **Status**: done — `ago-console#262` (`f67882f`). Independently re-verified by the managing session
  before merging: diff reviewed line-by-line (the new badge/Alert/checkedAt block correctly placed
  before the `justConnected` one-time-secrets conditional so it renders regardless of which
  "connected" source fired), and the full `ago-console` command set re-run directly — `typecheck`/
  `lint` clean, 1535/1535 tests (141 files), `ux-gate` 67 passed / 9 skipped — exact match to the
  worker's own report.
- **Depends on**: `25-175` (the API now returns `Verified`/`Unreachable`/`RefusalReason`/`CheckedAt` -
  this item only surfaces what already exists on the wire)
- **Found**: 2026-09-20, by the worker landing `25-175` - checked fresh against the real
  `VkChannelPage.tsx` (not assumed from `25-178`'s identical MAX finding).

## What is actually true today

`ago-chat`'s VK status route (`25-175`) reports `Verified`/`Unreachable`/`RefusalReason`/`CheckedAt` on
every read. `ago-console`'s `VkChannelPage.tsx` shows only a plain `Connected`/`Connected since` badge -
a tenant whose VK token has been revoked keeps seeing a green "Connected" badge with no indication
anything is wrong. `TelegramChannelPage.tsx` is the direct precedent for the three-state badge
(`unreachable` / `verified` / `unverified with reason`) this screen should adopt instead - `25-178`
(MAX's identical console gap) names the exact lines to mirror.

## Scope

- Widen `VkChannelStatusDto` (or whatever this console's own equivalent type is named - check
  `vkChannelApi.ts` for the exact name) to the same four extra fields the other two channel DTOs now
  carry.
- `VkChannelPage.tsx` renders the same three-state badge `TelegramChannelPage.tsx`/`25-178`'s planned
  `MaxChannelPage.tsx` change do - reuse that component's own `Alert`/badge pattern and add VK-specific
  i18n strings rather than reusing Telegram's or MAX's.

## Out of scope

- WhatsApp/Avito's own console screens - each gets its own item once its own API half
  (`25-176`/`25-177`) lands, if real.
- Any change to the API response shape - `25-175` already shipped it.
- Bundling this with `25-178` - MAX and VK are different screens, different files, different i18n
  strings; one promise each (`CLAUDE.md` rule 15).

## Done when

- [x] `VkChannelStatusDto` (or its real name) carries `verified`/`unreachable`/`refusalReason`/`checkedAt`.
      — `vkChannelApi.ts`, widened to the same 7-field shape as MAX/Telegram.
- [x] `VkChannelPage` shows an unreachable badge, a verified badge, or an unverified badge with the
      stated reason, matching whichever of the three the API reports - proven by a component test
      exercising all three states, the level `TelegramChannelPage.test.tsx` already proves its own three
      states at. — `VkChannelPage.test.tsx`'s `connectedAndVerified`/`connectedButRefused`/
      `connectedButUnreachable` fixtures, with negative assertions.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` all green for `ago-console`. — re-run independently,
      see Status line above.
