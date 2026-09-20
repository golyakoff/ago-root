# 25-179 · The console never shows a VK channel's live verification state

- **Stage**: 25
- **Status**: ready
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

- [ ] `VkChannelStatusDto` (or its real name) carries `verified`/`unreachable`/`refusalReason`/`checkedAt`.
- [ ] `VkChannelPage` shows an unreachable badge, a verified badge, or an unverified badge with the
      stated reason, matching whichever of the three the API reports - proven by a component test
      exercising all three states, the level `TelegramChannelPage.test.tsx` already proves its own three
      states at.
- [ ] `npm run typecheck`/`lint`/`test`/`ux-gate` all green for `ago-console`.
