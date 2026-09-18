# 25-147 · A connected channel never records its own public address

- **Stage**: 25
- **Status**: done — `ago-chat#327`
- **Found**: 2026-09-18, scoping the author's own request for a Jivo-style "message us on Telegram/
  MAX/..." switcher in the widget. A bot token proves a tenant controls a channel; it is not, by
  itself, a link a browser can open. No channel today captures, stores, or exposes the one public fact
  (a bot's own `@username`, a business phone number) that a deep link needs - every provider's own
  live-verification call already fetches it and throws it away.
- **Depends on**: nothing. Migration lane (adds a nullable column). Touches `ago-chat` only.

## What is actually true today, per channel

- **Telegram**: `TelegramApiClient.GetMeAsync` is already called - twice, in fact: once at connect
  (`TelegramChannelEndpoints.cs:160`) and again on every console status read
  (`TelegramLiveTokenCheck`, `adr/0143`'s live-verify posture). `TelegramGetMeResult(bool Ok, string?
  RefusalReason)` (`TelegramApiClient.cs:157`) reads only success/failure from the response and
  discards the body - `getMe`'s own `username` field is sitting right there, unread.
- **MAX**: `MaxChannelEndpoints.cs:38-41`'s own doc comment claims MAX exposes only `POST
  /subscriptions` and `GET /updates` - **this is stale and wrong**. MAX's Bot API has a `GET /me`
  method (needs only the bot token `MaxApiClient.AddAuthorization` already attaches) that returns
  `user_id, first_name, username, is_bot, description, avatar_url, commands`. Correct that comment in
  this same change.
- **VK**: `VkChannelEndpoints.cs:119` already stores `ProviderAccountId` (the community's numeric
  group id) - a public VK deep link (`vk.me/club<id>`) can be built from data already on file, **no
  new VK API call needed**. Note for whoever picks this up: `VkDtos.cs`'s own remarks say the entire
  VK integration was written and has shipped without ever being exercised against a real VK token -
  verify the `vk.me/club<id>` link form live, against a real VK community, before trusting it.
- **WhatsApp**: `WhatsAppApiClient.GetPhoneNumberAsync` already requests `display_phone_number` at
  connect time and `WhatsAppChannelEndpoints.cs:125` keeps only `info.Id` (the Meta-internal
  `phone_number_id`, an inbound-routing key - never expose this one). Capture `display_phone_number`
  too, even though no console page exists yet to let a tenant actually connect WhatsApp (a separate,
  larger gap, not this item's problem) - it costs nothing to keep a fact already in hand, and it makes
  a later console screen additive rather than needing this same investigation redone.
- **Avito**: `AvitoUserInfoSelf` (`AvitoDtos.cs:127`) returns only a numeric account id, which produces
  no public deep-link URL Avito itself documents. **Store nothing for Avito, and record in code why**
  - do not invent a link that does not exist.

## Scope

- `ChannelCredential` (`Ago.Chat.Domain`) gains `public string? PublicHandle { get; }`, set at
  `Register`, defaulting to `null` like `ProviderAccountId`/`RefreshTokenCiphertext` already do - an
  intrinsic fact with exactly the credential's own lifecycle, not a side table.
- Capture it at connect time for Telegram (parse the `username` the existing `getMe` call already
  gets), MAX (add the new `GetMeAsync` call, mirroring `MaxApiClient.SubscribeWebhookAsync`'s own
  shape), and WhatsApp (keep `display_phone_number` instead of discarding it). Derive it for VK from
  the already-stored `ProviderAccountId` - decide in this item whether that derivation happens at
  connect time (stored once) or at read time in `25-148`'s own new read store (computed, never
  stored) and say which, and why.
- Backfill Telegram's handle on its own existing live status read (it already re-calls `getMe` every
  time a tenant loads `/channels/telegram`) - a tenant who connected before this item ships gets a
  handle the next time they look at that screen, no reconnect required.
- Correct `MaxChannelEndpoints.cs`'s stale "no side-effect-free call" comment. Do not use the new
  `GET /me` call to also build MAX's own live-status-check parity with Telegram (`23-36`/`adr/0143`) -
  that is real, valuable, and its own separate item; naming it here is enough.
- Migration: one nullable column, additive, no backfill required for existing rows (`NULL` is the
  correct value for "not yet known").

## Where this is likely to go wrong

- **Never store or expose `phone_number_id` (WhatsApp) or any other provider-internal routing id as
  if it were the public handle** - `PublicHandle` is specifically the fact a stranger could already
  see or dial, not a credential-adjacent id.
- **Avito gets nothing, deliberately** - resist the temptation to store its numeric account id "just
  in case"; it produces no usable link and would only invite a later reader to assume otherwise.
- This item makes no visitor-facing or console-facing change - it only makes a fact available for
  `25-148` to read. Confirm no existing response (connect, status) gains a new property.

## Done when

- [x] Connecting Telegram stores the bot's `username`; an already-connected tenant's handle backfills
      on the next status read
- [x] Connecting MAX stores its bot `username`, via a new, correctly-documented `GET /me` call
- [x] VK's handle is available (stored or derived - this item's own decision) from the already-stored
      `ProviderAccountId`, with no new VK API call
- [x] Connecting WhatsApp stores `display_phone_number`
- [x] Avito stores nothing, with the reason recorded in a code comment
- [x] `phone_number_id` and every other provider-internal id stay exactly as private as before -
      confirmed by the existing `ChannelPortTests.MaxChannelResponses_CarryNoTokenOrSecretProperty`-
      style arch test still passing unchanged
- [x] No existing connect/status response gains a new property

## Outcome

`ChannelCredential.PublicHandle` (nullable, one additive migration). MAX's own `GetMeAsync` is a new,
best-effort call - never a connect-time gate, since it is genuinely new API surface MAX's flow never
exercised before. VK's handle is deliberately **not stored** - derived at read time in `25-148` from
`ProviderAccountId`, so it can never drift from it. Full suite green (Domain 741, Application 1388,
FakeCrm 21, Architecture 50, Concurrency 89, Integration 1351). `ago-chat#327`.
