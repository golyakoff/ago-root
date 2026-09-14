# 25-91 · The attachment download route has no real-HTTP test of its own

- **Stage**: 25
- **Status**: ready
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

- [ ] A real-HTTP integration test (`TestServer`, the same shape `OwnerDownloadBlockExemptionEndpointTests`
      or `RouteHandlerDiRegistrationTests` (`25-07`, `adr/0170`) already establish for other routes)
      exercises `GET /api/v1/attachments/{id}` for at least: success (presigned URL returned),
      `Attachment.NotFound` → `404`, `Attachment.NotReady` → its mapped code, `Attachment.Removed` →
      `410`, `Attachment.DownloadBlocked` → `403`.
- [ ] Decide, and record the decision: is a single exhaustive "every `ErrorExtensions.ToProblem` case
      resolves to its intended status" test worth building generally (closing this failure shape for
      every route at once, not just this one), or is per-route real-HTTP coverage the right level —
      state the reasoning either way rather than defaulting silently to the narrower fix.
