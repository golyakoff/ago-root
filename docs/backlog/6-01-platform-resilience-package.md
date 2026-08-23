# Ago.Platform.Resilience: a real shared package, not ad hoc Polly per project

- **Stage**: 6
- **Status**: ready
- **Depends on**: nothing - `ago-platform` only

## Goal

`Ago.Platform.Resilience` exists as `repositories.md` already says it should - a real project with
reusable retry/timeout/circuit-breaker/bulkhead policy builders behind a small, explicit surface,
consumed by every infrastructure adapter that talks to something outside our own process. After this
item, adding a new resilient boundary (the webhook dispatcher, `6-05`) means composing existing
building blocks, not writing a fourth ad hoc `ResiliencePipelineBuilder`.

## Context to read first

`architecture/resilience.md` in full - the boundary table and "patterns we deliberately do not use"
both constrain what this package needs to expose. `naming-and-structure.md`'s repository layout
(`Ago.Platform.Resilience/ timeout, retry, circuit breaker, bulkhead policies`). The two existing,
duplicated implementations this item replaces: `Ago.Platform.Caching.Redis/ServiceCollectionExtensions.cs`'s
`BuildResiliencePipeline()` and `Ago.Platform.Storage.S3/ServiceCollectionExtensions.cs`'s own -
same shape (`Polly`'s `ResiliencePipelineBuilder`, retry + timeout + circuit breaker), built
independently, no shared code, no bulkhead concept in either. `CLAUDE.md`: "do not invent numbers,
benchmarks... measure or stay silent" - every default this item ships is a documented starting point,
not a tuned number.

## Scope

- `Ago.Platform.Resilience` project: a small builder API over `Polly` (already the chosen library -
  both existing pipelines use it, no reason to introduce a second resilience library) - something
  like `ResiliencePolicyBuilder.WithRetry(...).WithTimeout(...).WithCircuitBreaker(...).WithBulkhead(...).Build()`,
  returning a `ResiliencePipeline` `Ago.Platform.Abstractions`-facing callers already know how to use
  (`resilience.execute Async(...)`, matching `S3FileStorage`'s existing call shape - no port-signature
  change needed at every existing call site).
- **Bulkhead**, the one pattern named in `resilience.md`'s table that nothing has implemented yet
  (`Polly.Bulkhead` or `Polly`'s v8 rate-limiter-based equivalent - confirm which ships in the
  `Polly` version already referenced, `Directory.Packages.props`).
- Refactor `Ago.Platform.Caching.Redis` and `Ago.Platform.Storage.S3` to consume the shared builder
  instead of their own private `BuildResiliencePipeline()` - same configured values, same behaviour,
  proving the extraction is real rather than parallel. Not a behaviour change; a dedup.
- Options-bound configuration per named pipeline (`Resilience:Redis:*`, `Resilience:S3:*`, and the
  new `Resilience:Webhooks:*` `6-05` will add), validated at startup - matching every other options
  class in this codebase (`naming-and-structure.md`).

## Out of scope

- The webhook dispatcher's own policy *values* (per-endpoint breaker thresholds, per-tenant
  concurrency cap) - `6-05`'s job, this item only ships the building blocks.
- Any change to `Ago.Platform.Messaging.*`'s own retry handling (`RetryPolicy`, the outbox
  redelivery shape) - that is a different, already-working mechanism (dead-letter after N attempts,
  `messaging.md`), not something this item folds in just because both involve "retry."
- A service mesh, or moving any of this to the infrastructure layer (ingress, sidecar) -
  `resilience.md`'s own "patterns we deliberately do not use" already rejected this.

## Done when

- [ ] `Ago.Platform.Resilience` ships with unit tests for each policy in isolation (a retry that
      gives up after N attempts, a timeout that actually cancels, a breaker that opens after the
      configured failure ratio and half-opens after `BreakDuration`, a bulkhead that rejects beyond
      its concurrency limit) - `Polly`'s own test doubles/fault injection, no real network needed.
- [ ] `Ago.Platform.Caching.Redis` and `Ago.Platform.Storage.S3` both build on the shared package;
      their own existing tests still pass unchanged (proving behaviour didn't shift).
- [ ] `Ago.Platform.Architecture.Tests` (or a new equivalent) asserts no infrastructure project builds
      its own `ResiliencePipelineBuilder` directly - the shared package is the only place that type
      name may appear outside `Ago.Platform.Resilience` itself.
- [ ] `CHANGELOG.md` entry, version bump (`repositories.md`'s SemVer rule) - this is new public API.

## Open questions

None - the shape follows directly from the two existing implementations being unified, and
`resilience.md` already specifies which patterns are needed. `Polly`'s bulkhead API surface (whether
it is `Polly.Bulkhead`'s classic package or v8's rate-limiter-based approach) is an implementation
detail to confirm against whatever `Polly` version `Directory.Packages.props` already pins, not a
design decision.
