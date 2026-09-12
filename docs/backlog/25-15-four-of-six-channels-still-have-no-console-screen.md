# 25-15 · Four of six channels still have no console screen

- **Status**: done — `ago-console#212`
- **Verified**: 2026-09-12 — confirmed in `ago-console/src/pages/`: `TelegramChannelPage.tsx` and
  `MaxChannelPage.tsx` (plus their own `.test.tsx` and `src/api/*ChannelApi.ts`) are real and shipped.
  No `VkChannelPage`/`EmailChannelPage`/`WhatsAppChannelPage`/`AvitoChannelPage` exists anywhere in
  `ago-console`. Confirmed in `ago-chat/src/Ago.Chat.Api/Channels/`: `VkChannelEndpoints.cs`,
  `WhatsAppChannelEndpoints.cs` and `AvitoChannelEndpoints.cs` are real, working backend adapters with
  no console counterpart — matching the item's own claim for three of the four. Email differs from the
  other three: it has `Ago.Chat.Infrastructure.Email/EmailChannelAdapter.cs` (inbound routing only, no
  `EmailChannelEndpoints.cs`/connect-a-token flow the way Telegram/MAX/VK/WhatsApp/Avito each have) —
  worth the dispatched worker reading before assuming Email fits the same "connection screen" shape as
  the other three.
- **Date found**: 2026-09-09, the remainder of `25-09` once MAX shipped
- **Depends on**: none — `23-36` (Telegram) and `25-09` (MAX) already establish the shape to follow

## What's left

Telegram and MAX both have console connection screens now. VK, Email, WhatsApp and Avito each still
have a working backend adapter (`14-08`/`14-09`/`14-10`/`14-11`) and no way for a tenant to connect
one without the API — the same gap `23-36` first named for all six, now narrowed twice.

## Scope

Whichever of the four comes first gets a screen following `TelegramChannelPage`'s discipline
(`23-36`'s own text, restated by `25-09` and still true): the token is never echoed back, "connected"
means the provider agreed (verified live wherever the provider's own API makes that honest — `25-09`'s
own finding that MAX cannot support Telegram's three-state check is the precedent for checking rather
than assuming each channel can), disconnect unlinks rather than deletes.

## Where this is likely to go wrong

- **Each channel really is a different shape.** `25-09`'s own finding: MAX's request shape looked
  identical to Telegram's on paper, but needed an extra webhook-subscribe step and had no status route
  at all. Read the actual backend adapter and its `*ChannelEndpoints.cs` before assuming any of VK,
  Email, WhatsApp or Avito matches Telegram's or MAX's shape.
- **WhatsApp and Avito are structurally further from Telegram than VK is** (`23-36`'s own original
  finding: WhatsApp goes through Meta's own onboarding, Avito is an account rather than a bot) — the
  easiest next pick is not necessarily the most useful one; state which and why, as `25-09` did.
- **Prioritise by what a tenant would actually ask for first**, not by adapter age or ease of build.
  This item does not decide which of the four goes first.

## Done when

- [x] At least one more channel (of VK, Email, WhatsApp, Avito) has a console connection screen.
- [x] Which channel, and why it went first, is stated rather than assumed.

## Outcome

**VK went first.** The backend worker read all three candidates' real endpoint code
(`ago-chat/src/Ago.Chat.Api/Channels/`) rather than assuming any matched Telegram's/MAX's shape: VK
needs exactly one secret (a community access token), validated live via VK's own `groups.getById`
before anything is written — no OAuth dance. WhatsApp needs a second value (`phoneNumberId`) obtained
from Meta's own onboarding; Avito is a real OAuth access/refresh token pair plus a programmatic
webhook-subscribe step with rollback. VK is the smallest, most honest "one channel, all the way,"
matching the reasoning `23-36`/`25-09` used to pick Telegram then MAX.

**A real, bigger-than-`25-09` gap found along the way, filed separately rather than worked around
silently**: `VkChannelEndpoints` (and `WhatsAppChannelEndpoints`/`AvitoChannelEndpoints`, checked
identically) map only `POST`/`DELETE` — no `GET` status route at all, unlike Telegram/MAX which both
back one with the already channel-neutral `GetChannelCredentialStatusHandler`. `VkChannelPage`
(`ago-console`) adapts honestly rather than faking persistence it doesn't have: the connect form
always shows (no status load on mount), a successful connect renders the credentials/disconnect view
for that page visit only (nothing persists across a reload), and an `AlreadyConnected` refusal gets
its own explanatory hint. The missing `GET` route itself is `25-65` — small, low-risk backend work,
deliberately out of this frontend-only item's scope.

Token discipline matches `TelegramChannelPage`/`MaxChannelPage`: the community's own access token is
sent once and never appears in any response this screen parses.

**A real CI catch, fixed in the same PR**: the new `navChannelsVk` string ("Сообщество VK") tripped
`ux-gate`'s "no untranslated interface text" check — the same shape `MAX`/`Telegram`/`WhatsApp` each
needed when first added. `VK` joined `ux-gate/lib/i18nCompleteness.ts`'s own brand-name exemption
list, the identical treatment its own doc comment already gives the other three
`Ago.Chat.Domain.ChannelKind` members.

**Verification** (`ago-console-25-15`, independently re-run by the managing session after a rebase
onto `origin/main` post-`25-63`): `tsc -b --noEmit` clean, `eslint src ux-gate` clean, `vitest run`
122 files / 1275 tests (0 failed), `vite build` clean (231.08 KB gzipped), `ux-gate` 63 passed / 5
skipped after the exemption fix. `VkChannelPage.test.tsx`'s 8 new-behavior cases were proven
fails-before: red against a stub with no connect/connected/disconnect/copy/already-connected-hint
logic, green with the real implementation restored.
