# Rate limiting: per-site and per-visitor token buckets

- **Stage**: 3
- **Status**: ready
- **Depends on**: `3-04-caching-layer.md` - same external technology (Redis), same
  `Ago.Platform.Caching.Redis` project (`clean-architecture.md`'s "one project per external
  technology" rule), reuses its connection setup.

## Goal

Message sends, widget handshakes, and file-upload initiations are limited per-site and
per-visitor via an atomic Redis-backed token bucket. Application code asks "may this happen?" and
gets a decision plus a retry-after, never touching Redis directly (`caching.md`'s Rate limiting
section).

## Context to read first

`docs/architecture/caching.md`'s "Rate limiting and counters" section, `edge.md`'s "What the edge
is responsible for" (coarse, cluster-protecting limits live at the edge; per-tenant limits live
here because they need domain knowledge the edge does not have).

## Scope

- `IRateLimiter` in `Ago.Platform.Abstractions`: `Task<RateLimitDecision> CheckAsync(RateLimitKey
  key, CancellationToken ct)` returning an allow/deny decision plus a retry-after `TimeSpan`. No
  domain concept in the port itself - the caller supplies the key and the bucket parameters.
- Implementation in `Ago.Platform.Caching.Redis` (alongside `ICache` - same technology, same
  project): a Lua script doing the atomic check-and-decrement in one round trip, per `caching.md`.
- Two call sites, of the three `caching.md` names: message send (per-visitor and per-site) and
  widget handshake (per-site) - the only two that exist as real endpoints today. File-upload
  initiation is the third named target, but attachments do not exist yet (`file-storage.md`'s
  presigned-upload flow is Stage 5) - wire the limiter into that endpoint when it is built, not
  before; do not invent a placeholder endpoint just to exercise the limiter.
- `429` with a `Retry-After` header on the REST paths; the SignalR equivalent (a `HubException`
  carrying the retry-after) on hub methods, since a hub cannot return an HTTP status.

## Out of scope

- Ingress-level rate limiting (`edge.md` names it as a separate, coarser mechanism at the Gateway)
  - not this repository's concern for this slice.
- Making the bucket parameters (capacity, refill rate) configurable per-site via an admin API - no
  roadmap stage names a settings UI yet; hardcode sane defaults in configuration for now, per-site
  overrides are a later, explicitly-scoped feature if the author asks for one.

## Done when

- [ ] `Ago.Chat.Concurrency.Tests`: N concurrent requests against one bucket - exactly the
      configured capacity succeeds, the rest are denied with a retry-after, at any concurrency
      level (the atomic-check-and-decrement claim, proven the same way `2-05`'s idempotency and
      `3-04`'s stampede protection are proven: real concurrency, not a sequential loop).
- [ ] A denied request's retry-after is honoured: waiting that long and retrying succeeds.
- [ ] `Ago.Chat.Integration.Tests`: both call sites (send, handshake) are actually wired to a
      limiter check, not just the port existing unused.
- [ ] `docs/architecture/caching.md`'s Rate limiting section gets the "shipped" treatment.

## Open questions

None.
