# 25-177 · An Avito channel's status screen never actually asks Avito anything

- **Stage**: 25
- **Status**: ready — **one open question below needs the author's decision before implementation**
- **Depends on**: nothing (independent of `25-174`/`25-175`/`25-176`)
- **Found**: 2026-09-20, alongside the other three - `AvitoChannelEndpoints.cs`'s own doc comment names
  the identical `25-65` gap for Avito too, worded almost identically to VK's own note.

## What is actually true today

`AvitoChannelEndpoints.HandleStatusAsync` reports only whether an active credential row exists.
`AvitoApiClient.GetSelfAsync(accessToken, ...)` is called exactly once, at connect time, to validate the
token - its own doc comment states plainly that re-asking it on every status read "would cost a tenant a
live Avito call just for looking at this screen, for a richness this item was never asked to add,"
mirroring VK's own `25-65` note exactly.

**Avito is genuinely not like the other three, in one specific way that changes this item's shape.**
Every other channel (Telegram/MAX/VK/WhatsApp) holds one durable token. Avito holds an OAuth
**access/refresh pair** (`ChannelCredential.RefreshTokenCiphertext`), and its access token *expires* -
`AvitoApiClient` already throws `AvitoAccessTokenExpiredException` specifically on a 401, and
`AvitoChannelAdapter`'s own send path already has a proven "expired → refresh once via
`RefreshAccessTokenAsync` → retry" pattern (`AvitoChannelAdapter.cs`, catching that exception around its
first send attempt). A live status check has to decide what an *expired-but-refreshable* token reports -
that is not one of Telegram's three outcomes (`Verified`/`Refused`/`Unreachable`), it is a fourth,
Avito-specific state this item's own design has to name rather than force into the existing shape.

**Also unlike Telegram/MAX/WhatsApp: Avito gets no `PublicHandle`, deliberately, per `25-147`'s own
decision** (`AvitoUserInfoSelf.Id` is a numeric seller id with no public deep-link Avito itself
documents) - so, like VK, this item is pure status-richness, never a backfill.

## Open question - needs the author's decision, not assumed

**Should a status read that finds an expired access token silently refresh it (writing a new
`AccessTokenCiphertext`/`RefreshTokenCiphertext` to the credential row) as a side effect of an operator
merely opening this screen, or should it only *report* "needs reconnecting" and leave the refresh to the
next real send attempt (`AvitoChannelAdapter`'s own existing path)?**

The other three items in this bundle (`25-174`/`25-175`/`25-176`) are pure reads with no write side
effect risk beyond the existing `PublicHandle` backfill pattern this codebase already accepts. A status
read that refreshes a token is a write triggered by a screen view - a real behavior change worth stating
explicitly rather than building either way by default. Recommendation, not a decision: report the
expired state without refreshing (matches the other three's "read-only" character, and the existing send-
path refresh already covers the case that actually matters - the channel keeps working); but the
opposite reading (refresh eagerly so the status screen itself never shows a stale "expired" a moment
before the next real message would have silently fixed it) is a legitimate alternative the author may
prefer.

## Scope

- An `AvitoLiveTokenCheck` (or equivalent), reusing `AvitoApiClient.GetSelfAsync` and the existing
  `AvitoAccessTokenExpiredException`/`RefreshAccessTokenAsync` mechanism `AvitoChannelAdapter` already
  proves works - not a second, parallel refresh implementation.
- `AvitoChannelEndpoints.HandleStatusAsync` calls it on every read, reporting whichever outcome shape is
  decided above.
- **No `PublicHandle` write anywhere in this item** - unchanged from today, per `25-147`.

## Out of scope

- MAX, VK, WhatsApp's own equivalent gaps - `25-174`, `25-175`, `25-176`.
- Any change to `AvitoChannelAdapter`'s own existing refresh-on-send behavior.

## Done when

- [ ] The open question above is answered before implementation starts.
- [ ] An Avito status read with a good, unexpired token reports `Verified: true`.
- [ ] An Avito status read with a genuinely revoked token (not merely expired) reports `Verified: false`
      with a stated reason.
- [ ] An Avito status read with an expired-but-refreshable token reports the outcome the open question
      above settled on - refreshed-and-verified, or a distinct "needs reconnecting" state - never
      silently collapsed into a plain refusal.
- [ ] An Avito status read when Avito (or this deployment's egress) is unreachable reports
      `Unreachable: true`, distinct from a refusal.
- [ ] `dotnet build`/`format`/`test` green for `ago-chat`; `ago-console` only if `AvitoChannelPage`
      needed a change.
