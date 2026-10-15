# 26-330 · [chat-api] A caller can quote the trace of any request: `X-Trace-Id` and a real `traceId`

- **Stage**: 26
- **Status**: in review — PR on `golyakoff/ago-chat`, branch `feat/26-330-trace-id-in-api-responses`
- **Found**: 2026-10-15, while asking "how can an API request be traced".

  The API already exports traces (`AddPlatformObservability` → OTLP → Jaeger, `adr/0025`), but a caller
  had no way to say *which* trace was theirs. The only id in a response was a problem body's `traceId`,
  populated from `HttpContext.TraceIdentifier` — Kestrel's connection/request counter
  (`0HN...:00000001`), which Jaeger does not index. A support ticket quoting it led nowhere.

**Done when**

- [x] `traceId` in a problem body is the W3C trace id of the request's server activity; falls back to
      `TraceIdentifier` only when nothing traces the request.
- [x] Every response of a traced request carries `X-Trace-Id`, including 4xx/5xx and CORS-rejected ones.
- [x] `X-Trace-Id` is in the per-site CORS policy's exposed headers, so page JS can read it.
- [x] Unit-level tests for the header, the body and the untraced fallback; CORS assertion added to the
      existing provider test.
- [x] `docs/conventions/api-design.md` states the contract.
- [ ] Seen live: one real request, its `X-Trace-Id` pasted into Jaeger, finds the trace. **Not done in the
      session that wrote this** — no Docker there (`local-dev.md`); to be ticked by whoever runs the
      compose loop.

**Deliberately not here**

- *Not trusting an incoming `traceparent`* (starting a fresh trace at the public edge and linking the
  caller's id). ASP.NET Core's hosting layer parses `traceparent` itself before any middleware runs, so
  this is not a middleware — it needs the activity replaced or a custom sampler, and deserves its own
  ticket and ADR once someone has measured whether untrusted `traceparent` is a real problem for the
  widget's third-party pages. Today a caller can still choose the trace id and sampled flag of its own
  request.
- *`AddPlatformObservability` for `ago-calendar` and `ago-analytics`*, and a generic-host variant
  (`adr/0046`'s named gap).
