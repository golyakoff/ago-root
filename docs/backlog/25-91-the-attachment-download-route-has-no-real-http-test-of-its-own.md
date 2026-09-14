# 25-91 · The attachment download route has no real-HTTP test of its own

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session before merging: `dotnet format
  --verify-no-changes` clean, `dotnet build -c Release` 0 warnings/0 errors, full `dotnet test`
  3392/3392, matching the worker's own count exactly (Domain 698, Application 1287, FakeCrm 21,
  Architecture 46, Concurrency 88, Integration 1252). No production code changed; no new bug found.
  A genuine follow-up the worker recommended — a general, honest audit of every error code
  `ErrorExtensions` does not map — is filed with its own number: `25-98`.
- **Depends on**: nothing
- **Found**: 2026-09-14, while landing `25-83` — the worker building the hard download-block gate
  needed to prove `Attachment.DownloadBlocked` actually reaches a caller as HTTP `403` (not the
  `500` `ErrorExtensions.ToProblem` was silently falling through to, `25-83`'s own defect #1) and
  discovered, while writing that proof, that **nothing in this codebase exercises
  `GET /api/v1/attachments/{id}` over real HTTP, for any outcome** — success, `404`, `403`, any of
  it. The `403` mapping bug had been live and untested since the handler was written.

## What is actually true

`GetAttachmentDownloadUrlHandler` and its route are covered at the Application layer (handler unit
tests against fakes) and nowhere else. Every other error code this handler can return —
`Attachment.NotFound`, `Attachment.NotReady`, `Attachment.Removed` (`23-82`), and now
`Attachment.DownloadBlocked` (`25-83`) — has only ever been asserted as a `Result` value, never
checked against what `ErrorExtensions.ToProblem` actually turns it into over the wire. `25-83`'s own
two real HTTP-status bugs (`Attachment.DownloadBlocked` and
`Site.DownloadBlockExemptionReasonRequired` both falling through to `500`) were only caught because
that item happened to add a *different* route's HTTP test
(`OwnerDownloadBlockExemptionEndpointTests`) and a worker went looking at the neighboring switch
statement afterward — not because this route had a test that would have caught its own bug.

## Why this is worth its own item

`23-72`'s own remarks already name this exact failure shape for `Operator.NotFound` — a code that
exists, is asserted at the Application layer, and silently falls through the API's own error
mapping to a wrong status nobody's test could catch. That gap keeps reproducing route-by-route
because there is no general test naming "every error code a handler can return resolves to the
status this codebase intends," only ad hoc coverage wherever an unrelated item happens to add an
HTTP test that brushes against it.

## Done-when

- [x] A real-HTTP integration test (`TestServer`, the same shape `OwnerDownloadBlockExemptionEndpointTests`
      or `RouteHandlerDiRegistrationTests` (`25-07`, `adr/0170`) already establish for other routes)
      exercises `GET /api/v1/attachments/{id}` for at least: success (presigned URL returned),
      `Attachment.NotFound` → `404`, `Attachment.NotReady` → its mapped code, `Attachment.Removed` →
      `410`, `Attachment.DownloadBlocked` → `403`.
      **`AttachmentDownloadEndpointTests` (`ago-chat`, `tests/Ago.Chat.Integration.Tests/`)** - five
      `[Fact]`s, a real `TestServer` over `AttachmentEndpoints.MapAttachmentEndpoints` (the actual
      production route group, not a hand-transcribed subset), a real Postgres
      (`OperatorOidcFixture`), and a real visitor JWT (`JwtTokenService`/`TestSigningKeys`, the
      same minting `TokenSchemeSeparationTests` already uses). All five reached through the visitor
      side of the dual-scheme route rather than the operator side - see the test file's own class
      remarks for why that still exercises the identical `ToProblem` wiring every error code in this
      item's own list goes through. `Attachment.NotReady`'s "mapped code" turned out to be `409
      Conflict`, not `403`/`400` - read directly off `ErrorExtensions.ToProblem`'s own switch rather
      than assumed. Confirmed with a fails-before proof per test (see the worker's own report): each
      status mapping was individually reverted in `ErrorExtensions.cs` (and, for the success case, the
      route mapping itself was removed), rebuilt, the corresponding test observed to fail (`500` or
      `405` in place of the intended status), then restored - the `Attachment.DownloadBlocked` case is
      a literal re-creation of `25-83`'s own original bug, confirmed to reproduce and confirmed fixed.
- [x] Decide, and record the decision: is a single exhaustive "every `ErrorExtensions.ToProblem` case
      resolves to its intended status" test worth building generally (closing this failure shape for
      every route at once, not just this one), or is per-route real-HTTP coverage the right level —
      state the reasoning either way rather than defaulting silently to the narrower fix.
      **Decided: per-route real-HTTP coverage stays the right level for now; a general exhaustive
      `ToProblem` test is a real idea but not a safe "natural, closely related extension" of this
      item.** The reason is not cost - a direct-call test with no `TestServer` at all
      (`ErrorExtensionsRetryAfterTests`' own shape: a bare `DefaultHttpContext`, `error.ToProblem(...)`,
      no hosting pipeline) would be cheap to write. The reason is that **the only sound source for
      "every error code, and its intended status" is independent of the switch under test**, and this
      codebase does not currently have one: `ErrorExtensions.cs`'s own inline comments are the closest
      thing to that documentation today, and several codes are *deliberately* left unmapped there as
      pre-existing, named debt (`Operator.SeatLimitReached`, `Billing.SeatCountUnchanged`,
      `Billing.InvalidSeatCount`, `Billing.SubscriptionNotFound`, `Billing.SubscriptionNotActive`,
      `Billing.PaymentProviderRefused`, among others the switch's own remarks name). A test built by
      enumerating every `*Errors`-shaped factory method via reflection and asserting "not `500`" would
      either have to hard-code that same exclusion list (silently freezing today's debt as
      permanently acceptable, the opposite of what `23-72`'s own remarks ask for) or flag genuine,
      already-known gaps as new failures on day one - neither is "closing this failure shape," both
      are a second, different-shaped item. Building that audit honestly - one line per code, cross-
      checked against what each code's own factory-method callers actually need, resolving each
      debt item's own fate on purpose rather than by construction - is real, valuable work, but it is
      `23-72`'s own scope restated, not this item's. Recommended as its own follow-up rather than
      folded in here **so it gets that dedicated write-up**, not because it is unimportant.
