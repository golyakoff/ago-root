# 25-177 · An Avito channel's status screen never actually asks Avito anything

- **Stage**: 25
- **Status**: ready — the open question below is decided by the author, 2026-09-20: refresh eagerly.
  See "Decision" below the question for the reasoning and the one risk this adds to Scope.
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

## Decision - the author, 2026-09-20: refresh eagerly

**A status read that finds an expired-but-refreshable access token refreshes it immediately** (writes a
new `AccessTokenCiphertext`/`RefreshTokenCiphertext` to the credential row), rather than only reporting
"needs reconnecting" and leaving the refresh to the next real send attempt. Chosen explicitly over the
"report only" alternative (the other three items in this bundle's own read-only character) because the
operator-facing cost of the alternative - a screen that shows "expired" for a channel that is, in
practice, perfectly healthy and about to silently fix itself on the next inbound message - was judged
worse than the one real risk this choice adds:

**The concurrency risk this decision accepts, and what Scope must do about it.** Avito's refresh tokens
are one-shot and rotate on use (`AvitoApiClient.RefreshAccessTokenAsync`'s own contract) - using one
invalidates it and issues a new one. Two concurrent status reads (two browser tabs, or an operator
double-clicking reload) both finding the same expired token could both attempt
`RefreshAccessTokenAsync` with the same, now-single-use, refresh token: the second call to actually reach
Avito loses the race and fails with a now-invalidated refresh token, even though the *first* call
succeeded and the channel is fine. **This must not surface as a hard failure or a "needs reconnecting"
state** - the implementation has to treat "the refresh token I just tried was already used" as "someone
else already refreshed this, re-read the row" (reload the credential and use whatever access token is
there now) rather than as a real error. Name this explicitly in the implementation rather than
discovering it only when two tabs happen to collide in testing.

## Scope

- An `AvitoLiveTokenCheck` (or equivalent), reusing `AvitoApiClient.GetSelfAsync` and the existing
  `AvitoAccessTokenExpiredException`/`RefreshAccessTokenAsync` mechanism `AvitoChannelAdapter` already
  proves works - not a second, parallel refresh implementation.
- On `AvitoAccessTokenExpiredException`, refresh immediately (per the Decision above) and persist the new
  access/refresh pair, then report `Verified: true` for the now-current token - never report the
  transient "was expired a moment ago" fact to the caller.
- **Handle a concurrent refresh-token-already-used failure as "someone else already refreshed this",
  not as an error** - reload the credential row and use whatever access token is there now, per the
  Decision's own concurrency note. A test forcing two concurrent status reads against the same expired
  token is part of Done-when, not optional.
- `AvitoChannelEndpoints.HandleStatusAsync` calls it on every read.
- **No `PublicHandle` write anywhere in this item** - unchanged from today, per `25-147`.

## Out of scope

- MAX, VK, WhatsApp's own equivalent gaps - `25-174`, `25-175`, `25-176`.
- Any change to `AvitoChannelAdapter`'s own existing refresh-on-send behavior.

## Done when

- [ ] An Avito status read with a good, unexpired token reports `Verified: true`.
- [ ] An Avito status read with a genuinely revoked token (not merely expired) reports `Verified: false`
      with a stated reason.
- [ ] An Avito status read with an expired-but-refreshable token refreshes it and reports
      `Verified: true` for the newly-current token - the caller never sees the transient expiry.
- [ ] Two concurrent status reads against the same expired token both succeed (one refreshes, the other
      detects its own refresh token was already rotated and re-reads rather than failing) - proven by a
      test that actually races two calls, not asserted from reading the code.
- [ ] An Avito status read when Avito (or this deployment's egress) is unreachable reports
      `Unreachable: true`, distinct from a refusal.
- [ ] `dotnet build`/`format`/`test` green for `ago-chat`; `ago-console` only if `AvitoChannelPage`
      needed a change.
