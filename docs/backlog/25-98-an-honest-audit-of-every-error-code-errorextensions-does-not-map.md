# 25-98 · An honest audit of every error code `ErrorExtensions` does not map

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session before merging: rebased onto
  current `main` clean, `dotnet format`/`build` clean, and the full `ago-chat` suite re-run
  independently at 3482/3482 (0 failed, 1 pre-existing skip from `25-99`) — an exact match to the
  worker's own claimed count, checked per project rather than only the aggregate. The one finding
  outside this item's own scope (`TenantSuspension.SessionRefused`, dead code) is filed as its own
  item, `25-100`.
- **Depends on**: nothing
- **Found**: 2026-09-14, while building `25-91` — that item's own second Done-when box asked whether a
  single exhaustive "every `ErrorExtensions.ToProblem` case resolves to its intended status" test was
  worth building generally, instead of the per-route real-HTTP coverage it actually built. It decided
  against folding the general test into itself, for a specific reason worth its own item.

## What is actually true

`ErrorExtensions.cs`'s own switch already leaves several codes deliberately unmapped, named in its own
inline comments as pre-existing debt — `Operator.SeatLimitReached`, `Billing.SeatCountUnchanged`,
`Billing.InvalidSeatCount`, `Billing.SubscriptionNotFound`, `Billing.SubscriptionNotActive`,
`Billing.PaymentProviderRefused`, among others the switch's own remarks name (grep for the codes not
covered before assuming this list is exhaustive — it is a floor, not a ceiling, the same caveat every
other "found while building X" item this evening has carried). `25-91` found and closed two more real
instances of this shape (`Attachment.DownloadBlocked`, `Site.DownloadBlockExemptionReasonRequired`,
both `25-83`'s own), and `23-72`'s own remarks name the identical failure shape for `Operator.NotFound`
in an unrelated context — this keeps reproducing route by route because nothing in this codebase
answers "every error code a handler can return, and the status it should resolve to" as one honest,
independently-sourced list.

## Why a naive reflection-built test would make this worse, not better

The tempting shape — enumerate every `*Errors`-shaped factory method via reflection, assert none falls
through to `500` — has no independent source for "and here is the status each one *should* have." Built
against today's switch, it would either have to hard-code the current exclusion list (silently freezing
today's known debt as permanently acceptable — the opposite of what this item exists to fix) or flag
every one of those already-known gaps as a new failure on day one, indistinguishable from a genuinely
new regression. Neither is "closing the failure shape."

## Scope

- A real, one-line-per-code audit: every error code a handler in this codebase can produce, cross-checked
  against what its own actual callers need (a specific HTTP status, chosen on purpose — not "whatever
  the switch happens to do today").
- For each currently-unmapped code found: either map it to its correct status in the same change, or
  record explicitly why it is deliberately left as `500` (or another status) — resolving each debt
  item's fate on purpose, not by omission.
- Once the audit is honest, decide whether a general test enforcing "every code maps to something, and
  new code must be classified before it ships" is worth building on top of it — this item's own
  Done-when does not presuppose the answer.

## Done when

- [x] Every `*Errors`-shaped factory method's error code in `ago-chat` has a recorded, deliberate answer
      to "what HTTP status should this be" — either already correct in `ErrorExtensions.cs`, fixed to be
      correct, or explicitly named as intentional debt with a reason, not silently absent from the list.
      **The real count: 165 error codes total** (read by reflection off every `*Errors`-shaped class in
      `Ago.Chat.Application` — `ConversationErrors`, `AiAddOnErrors`, `AcceptanceErrors`,
      `DemoTenantErrors`, `PriceCatalogErrors`, `PublishedDocumentErrors`, `RequiredDocumentErrors`,
      `TeamChatErrors` — not the six this item's own text named, which was confirmed to be a floor, not
      a ceiling, exactly as warned). Of those, **124 were already correctly mapped** (a hand spot-check
      of every status the codebase's own doc comments state explicitly — `402`, `403`, `404`, `409`,
      `410` — found no mismatch between a comment's stated status and the switch's own placement).
      **41 fell through to the `500` default with no line at all**, of which:
      - **33 reach a real HTTP endpoint's own `ErrorExtensions.ToProblem` call and are fixed** in
        `src/Ago.Chat.Api/Http/ErrorExtensions.cs`, each with the doc-comment reasoning that produced
        its status (the same "cite the code's own remarks and the closest existing group" discipline
        every prior entry in that file already uses) and a fails-before-proven test in the new
        `tests/Ago.Chat.Integration.Tests/ErrorCodeAuditStatusMappingTests.cs` (33 `[Fact]`s at the
        same no-`TestServer` level `DemoEndpointErrorStatusMappingTests`/`ErrorExtensionsRetryAfterTests`
        already establish for this exact method).
      - **7 never reach `ToProblem` at all** (`Message.InvalidBody`, `Message.InvalidContent`,
        `Message.Unavailable`, `Conversation.CreateRateLimited`, `TeamChat.Forbidden`,
        `TeamChat.InvalidBody`, `TeamChat.NotFound`) — every caller of each factory method is a SignalR
        hub (`VisitorHub`/`OperatorHub`), which translates through `HubException(error.Message)`
        directly and never runs through `IResult`/`ToProblem`. Recorded, with the reasoning, as a
        comment in `ErrorExtensions.cs`'s own switch and as an entry in the new
        `ErrorCodeMappingExemptions.cs`.
      - **1 is dead code** (`TenantSuspension.SessionRefused`) — no caller anywhere in the codebase,
        not even a test. Its own doc comment claims `AuthEndpoints.HandleVisitorSessionAsync`'s own
        refusal, but that method hand-builds `Results.Problem` directly and never goes through this
        vocabulary at all. Left unmapped rather than mapped to a guess (a status for a call nothing
        makes cannot be right or wrong); recorded the same way as the seven Hub-only codes, and named
        as a real follow-up below rather than fixed here (rule 15 - wiring `AuthEndpoints` onto the
        vocabulary, or deleting the dead method, is a second, unrelated promise).
- [x] A decision, stated and reasoned, on whether an enforcing test (new code must be classified before
      merge) is worth building now that the audit is honest — and if so, built.
      **Decided: yes, and built** — `tests/Ago.Chat.Architecture.Tests/ErrorCodeCatalog.cs`,
      `ErrorCodeMappingExemptions.cs` and `ErrorCodeMappingTests.cs`. Narrower than the naive shape
      this item's own text rejected: it does not assert a status is *correct* (still a human judgement
      call at review time, same as every other line in `ErrorExtensions.cs` was decided), only that
      every code produced by a `*Errors` factory method is either given a line in the switch or a
      reasoned entry in `ErrorCodeMappingExemptions` — "classified on purpose," not "classified
      correctly." That claim is sound now in a way it was not before this item: the exemption list is
      no longer copied from the switch it tests (which is what made the naive version circular), it is
      this item's own independently-derived set of the eight codes checked, by reading every caller, to
      never reach this method at all. `NoExemption_IsStale` keeps that list honest the same way
      `MessageOpacityExemptions`'/`TenantScopeExemptions`' own staleness checks already do for their
      rules. Fails-before proven for both the coverage test (reverted `ErrorExtensions.cs`, all 33
      fixed codes reported as unclassified) and the staleness test (a synthetic stale entry reported by
      name).
