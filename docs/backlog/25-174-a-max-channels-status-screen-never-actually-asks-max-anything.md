# 25-174 · A MAX channel's status screen never actually asks MAX anything

- **Stage**: 25
- **Status**: done — `ago-chat#343` (`3b69605`). Independently re-verified by the managing session before
  merging: diff reviewed line-by-line against `TelegramLiveTokenCheck`/`TelegramChannelEndpoints`, and
  the full `ago-chat` command set re-run directly (not trusted from the worker's own report) —
  `dotnet format`/`build` clean, all 7 test assemblies green, 3806/3806 tests.
- **Depends on**: nothing
- **Found**: 2026-09-20, while scoping the earlier "make all channels symmetric" ask - confirmed directly
  against the code rather than assumed from the item's own title (`ago-chat`'s `MaxChannelEndpoints.cs`
  already names this exact gap in its own doc comment, dated `25-09`/`25-147`).

## What is actually true today

`TelegramChannelEndpoints.HandleStatusAsync` re-verifies the bot token live on every read
(`TelegramLiveTokenCheck.RunAsync` → `TelegramApiClient.GetMeAsync`), reporting `Verified`/`Refused`/
`Unreachable` distinctly, and backfills `ChannelCredential.PublicHandle` from the response - all on the
same read, no reconnect required.

`MaxChannelEndpoints.HandleStatusAsync` does none of this - it reports only whether an active credential
row exists (`GetChannelCredentialStatusHandler`'s own channel-neutral answer). MAX's own `GET /me`
(`MaxApiClient.GetMeAsync`) already exists and is already called - but only once, best-effort, at
connect time (`HandleConnectAsync`), to seed `PublicHandle`. The class's own doc comment names the
missing piece explicitly: *"this item deliberately does not use it to give `HandleStatusAsync`
Telegram-style live-verification parity... that is a real, separate, valuable item of its own, named
here so it is not silently rediscovered."* This item is that one.

## Scope

- A `MaxLiveTokenCheck`, mirroring `TelegramLiveTokenCheck`'s own shape exactly (bounded timeout,
  three-outcome result: `Verified`/`Refused`/`ProviderUnreachable`) - wrapping `MaxApiClient.GetMeAsync`,
  which already returns a result the caller inspects rather than throwing on a terminal refusal (its own
  doc comment already draws the parallel to `TelegramApiClient.GetMeAsync`).
- `MaxChannelEndpoints.HandleStatusAsync` calls it on every read, the same place Telegram's own handler
  does, and backfills `PublicHandle` on a changed username - the identical `25-147` pattern
  `TelegramChannelEndpoints.HandleStatusAsync` already implements line for line (that method's own
  backfill block is the direct template).
- `MaxChannelStatusResponse` gains the same `Verified`/`Unreachable`/`RefusalReason`/`CheckedAt` fields
  `TelegramChannelStatusResponse` already carries - check whether a shared shape between the two response
  types is worth extracting, or whether the existing per-channel-response convention should just be
  repeated; name whichever is chosen rather than picking silently.
- **Reuse `MaxLiveTokenCheck.Timeout` as its own 5-second constant** - `TelegramLiveTokenCheck.Timeout`'s
  own reasoning (matched to `ChatModule.ConfigureChannelResilienceDefaults`'s boundary, not invented)
  applies identically here; do not invent a different number without a reason.

## Out of scope

- `HandleConnectAsync`'s own existing best-effort `GetMeAsync` call - unchanged, this item only adds the
  second call site.
- VK, WhatsApp, Avito's own equivalent gaps - filed separately (`25-175`, `25-176`, `25-177`), each with
  its own provider-specific shape (VK has no `PublicHandle` to backfill at all; WhatsApp's discovery call
  needs a `phoneNumberId` MAX's does not; Avito's tokens expire and need refresh, which none of the
  others do) - not one bundled item across four different provider APIs.
- The console's own `MaxChannelPage` (or equivalent) rendering the new fields - check whether it already
  renders `TelegramChannelPage`'s own generic problem-details/status surface (`25-160`'s own finding for
  a different item was that `ago-console` needed no change because the existing rendering already
  surfaces whatever the handler returns) before assuming new console work is needed here.

## Done when

- [x] A MAX status read with a good token reports `Verified: true` and the bot's current `@username`. —
      `MaxLiveTokenCheckTests`/`MaxChannelStatusLiveCheckTests` (`Ago.Chat.Integration.Tests`), the
      latter HTTP-level via a fake MAX host.
- [x] A MAX status read with a revoked/bad token reports `Verified: false` with a stated reason, not a
      generic forbidden/500. — `MaxChannelStatusLiveCheckTests.GetMaxStatus_WithARevokedToken_ReportsVerifiedFalseWithAStatedReason`.
- [x] A MAX status read when MAX (or this deployment's own egress to it) is unreachable reports
      `Unreachable: true`, distinctly from a refusal. — `...WhenMaxIsUnreachable_ReportsUnreachable_DistinctFromARefusal`.
- [x] `PublicHandle` updates on a status read the same way it already does at connect time, when the
      bot's own username has changed since the credential was created. —
      `GetMaxStatus_WithAGoodToken_ReportsVerifiedAndBackfillsTheChangedUsername`.
- [x] `npm`/`dotnet` full command sets both green. — `ago-chat`: `dotnet format`/`build` clean, all 7
      test assemblies green (754+1448+21+52+90+1441 = 3806 tests, 0 failed), re-run independently by the
      managing session. `ago-console` needed no change - `MaxChannelStatusDto` is a strict TS interface
      that silently ignores the new fields; surfacing them in `MaxChannelPage`'s UI is a real,
      **currently unfiled** follow-up, out of this item's own scope.
