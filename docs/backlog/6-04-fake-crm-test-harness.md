# A fake CRM with three personalities: hangs, 5xxs, disappears

- **Stage**: 6
- **Status**: ready
- **Depends on**: nothing - a standalone test double, built before `6-05` needs it so the dispatcher
  can be developed against real misbehaviour from day one, not bolted on after

## Goal

A small, real HTTP server - not a mock, an actual process a real request reaches - that can be told to
behave like the three ways a shop's CRM misbehaves in production: hang for a configured duration,
answer with a 5xx, or refuse the connection outright. `6-05`'s dispatcher and `6-06`'s load proof both
point at this instead of a real third party, and it is what makes "the breaker opens, the bulkhead
holds" a provable claim instead of an assertion about configuration.

## Context to read first

`roadmap.md`'s Stage 6 "Done when" - "with a CRM that hangs for 30 seconds on every call" is the exact
scenario this harness must produce on demand. `resilience.md`'s boundary table row for outbound
webhooks. `AttachmentFixture`/`MinioFixture`'s own precedent (`file-storage.md`) - this project's
established pattern for a lightweight, real (not mocked) dependency stood up for integration tests,
applied here to an HTTP server instead of an S3-compatible store.

## Scope

- A minimal ASP.NET Core (or even a raw `HttpListener`) app, `tests/`-scoped or a tiny standalone
  project under `ago-chat` (state which and why - a full project if `6-05`'s own integration tests
  and `6-06`'s load test both need to point a load-test tool at a *running* instance, not just
  something spun up in-process by xUnit).
- Three configurable personalities, selectable per request (a header or path segment the test/load
  driver sets, e.g. `X-Fake-Crm-Behavior: hang-30s|5xx|refuse`):
  - **Hangs**: holds the connection open for a configured duration before ever responding (or never
    responds within the test's own patience - the dispatcher's total timeout must be what ends it,
    not the fake server voluntarily giving up).
  - **5xxs**: an immediate `500`/`503`.
  - **Disappears**: refuses the TCP connection outright (closed port, or an immediate RST) -
    distinct from "hangs," since a real dead endpoint fails fast at the transport layer while a slow
    one fails slow, and a resilient dispatcher must handle both without conflating them.
  - A fourth, boring **succeeds** mode, since most of the dispatcher's own happy-path tests need one.
- Signature verification on the receiving side (checks the `X-Ago-Signature` header `6-03`'s ADR
  defines) - not because this project needs to prove *its own* signing works from the outside in, but
  because a fake CRM that never checks the signature would let a real signing bug through unnoticed.

## Out of scope

- Any persistence or delivery log of its own - this is a disposable test double, not a product.
- Configurable per-tenant behaviour (multiple fake endpoints behaving differently at once) - `6-05`'s
  own tests can stand up multiple instances/ports if that is ever needed; this item ships one
  behavior-switchable server, not a fleet.
- Load-generation itself (`k6`, or whatever this project's `load/` directory already uses, per
  `CLAUDE.md`'s "load-test run in `load/`") - `6-06`'s job to drive traffic *at* the dispatcher while
  pointed at this harness, not this item's.

## Done when

- [ ] All four personalities proven with a real HTTP client hitting a real running instance (not an
      in-process `TestServer` shortcut that never touches a real socket) - `hangs` genuinely blocks
      for the configured duration, `disappears` genuinely refuses the connection (a `SocketException`
      on the caller's side, not a fast HTTP error).
- [ ] Signature verification proven: a request with a tampered body or a stale timestamp is rejected
      by the harness's own check, matching whatever `6-03`'s ADR specifies for replay-window length.
- [ ] A short README (or this file's own close-out) states exactly how `6-05`/`6-06` are expected to
      point at it - command to run it, the header/path convention for selecting a personality.

## Open questions

None - scope follows directly from `roadmap.md`'s own named scenario list ("hangs, 5xxs,
disappeared").
