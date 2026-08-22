# Caching

Redis plays three separate roles in this system. Keeping them mentally separate matters, because
they have different failure semantics:

1. **Runtime coordination state** - connection registry, presence, typing. Ephemeral, rebuildable.
   Covered in `realtime.md`.
2. **Cache** - a copy of data that PostgreSQL owns. Covered here.
3. **Counters** - rate limits, quotas. Covered here.

Losing Redis entirely must degrade the system (slower, stale presence, reconnect storms), never
corrupt it. Any design where a Redis flush loses committed data is wrong by construction.

## The port

**Shipped in `3-04`**: `ICache` lives in `Ago.Platform.Abstractions` (not each product's own
`Application/Abstractions` - it is generic technical infrastructure, not chat-specific, the same
placement `IEventPublisher`/`IConnectionRegistry` already use) and is implemented in
`Ago.Platform.Caching.Redis`. Application code never sees `IConnectionMultiplexer`,
never sees a key string, and never sees a serializer - the same dependency rule as every other
external resource (`clean-architecture.md`).

```
Task<T?>  GetAsync<T>(CacheKey key, CancellationToken ct);
Task      SetAsync<T>(CacheKey key, T value, CacheEntryOptions options, CancellationToken ct);
Task<T>   GetOrCreateAsync<T>(CacheKey key, Func<CancellationToken, Task<T>> factory,
                              CacheEntryOptions options, CancellationToken ct);
Task      RemoveAsync(CacheKey key, CancellationToken ct);
```

`GetOrCreateAsync` is the only method most call sites should use, because it is the one that
implements stampede protection. Deliberately **not** `IDistributedCache`: its byte-array API pushes
serialisation into callers and has no single-flight story.

We do not use a generic `[Cacheable]` decorator over every handler. Caching is a per-use-case
decision with a per-use-case invalidation story; an attribute hides exactly the part that has to be
thought about.

## What we cache, and why each is safe to cache

Only the first row is shipped (`3-04`) - the other four are the plan, not yet built; add each as its
own small slice once a real caller needs it, following the same pattern this one proves.

| Data | TTL | Invalidation | Why it is cacheable |
|---|---|---|---|
| Site config (`public_key`, allowed origins, widget settings) | 5 min + jitter | Event `SiteSettingsChanged` | Read on every widget handshake, changed rarely. This is the hot one. **Shipped in `3-04`**: `GetSiteConfigByPublicKeyHandler` (`Ago.Chat.Application`), the widget handshake's site lookup (`POST /api/v1/visitor-sessions`). |
| Operator profile + capacity | 1 min | Event on change | Read on every assignment decision |
| Conversation metadata (participants, state) | 30 s | Event `ConversationAssigned` / `ConversationClosed` | Read on every inbound message |
| Recent message page (last N of a conversation) | 15 s | Write-through on new message | Reconnect storms re-request the same page |
| Visitor token validation result | 2 min | TTL only | Pure function of a row that never changes |

**Never cached**: anything used to make a write-side consistency decision. The assignment engine
reads `active_chats` from the database inside its transaction, never from Redis, because the whole
point of that path is an atomic check-and-increment (`concurrency.md`). Caching a value you then
compare-and-set is how portfolio projects quietly grow race conditions.

## Patterns we implement

- **Cache-aside** as the default. Read cache, miss, load, populate, return. **Shipped in `3-04`**:
  `RedisCache.GetOrCreateAsync`.
- **Stampede protection.** A miss on a hot key must not hit the database N times. **Shipped in
  `3-04`**: in-process single-flight (`ConcurrentDictionary<string, Lazy<Task<object?>>>`, keyed
  generically so one dictionary serves every `T`) plus a short cross-node `RedisLock` (`SET NX`
  acquire, a token-checked Lua-script release - a plain `DEL` would risk deleting a different
  holder's lock after this one's own TTL expired). The cross-node half is best-effort, not a
  guarantee - a lock-acquire failure or a lost race falls back to loading directly rather than
  blocking; proven for real under actual concurrency at the in-process level
  (`Ago.Chat.Concurrency.Tests.SiteConfigCachingStampedeTests` - 30 concurrent readers against a
  cold key, backing store hit once), not asserted. A real cross-node number is still a Stage 7 load
  test (cold cache + 1000 concurrent readers across replicas), not measured here.
- **TTL jitter.** Every TTL gets +/- 10% randomisation so that entries created together do not
  expire together and synchronise a thundering herd. **Shipped in `3-04`**: applied once, in
  `RedisCache`, never by a call site.
- **Event-driven invalidation.** Invalidation messages travel over the broker, so all nodes drop the
  key. This is a real use of the messaging layer, not a second-class path: `CacheInvalidated` is a
  normal integration event with the same at-least-once semantics. **Shipped in `3-04`**, split at
  the product/platform seam (`clean-architecture.md`'s qualifying rule) the same way `realtime.md`'s
  fan-out path is: `Ago.Chat.Worker`'s `SiteCacheInvalidationConsumer` maps `SiteSettingsChanged`
  (product-specific: which site) to `Ago.Platform.Caching.Redis`'s `CacheInvalidationPublisher`
  (generic: broadcast this key), which every node's `CacheInvalidationConsumer`
  (`SubscriptionMode.Broadcast`) picks up and drops locally. Both publishers call
  `IEventPublisher.PublishAsync` directly, bypassing the outbox - the same `adr/0020` reasoning
  already covers this: an invalidation is a derived, best-effort notification, and losing one is
  bounded by the entry's own TTL, never a correctness bug. `SiteSettingsChanged` itself has no
  producer yet - nothing changes a site's settings today (site administration is Stage 5) - so this
  path is proven by publishing the event directly in tests, the same "documented, not yet wired"
  status `realtime.md`'s `clientMessageId` has.
- **Negative caching** for "site not found" lookups, with a short TTL, so a bad script tag on a
  popular page cannot hammer the database. **Shipped in `3-04`**: `GetSiteConfigByPublicKeyHandler`'s
  own `LoadAsync` writes the negative result directly, with its own shorter `CacheEntryOptions`,
  which `ICache.GetOrCreateAsync`'s own contract leaves alone rather than overwriting with the
  caller's longer default TTL - the general mechanism a future negative-caching call site reuses
  without needing a second parameter on the port.
- **Two-level cache (Stage 7, measured).** In-process `MemoryCache` in front of Redis for site
  config. Only added if the load test shows Redis round-trips in the hot path; the accompanying
  cost is a bounded staleness window that must be written down, not discovered later.

## Rate limiting and counters

Per-site and per-visitor limits on message sends, widget handshakes, and file uploads. Implemented
as a token bucket in a Redis Lua script (atomic check-and-decrement in one round trip) behind an
`IRateLimiter` port. Application code asks "may this visitor send?" and gets a decision plus a
retry-after; it never knows Redis exists.

**Shipped in `3-05`** for the first two of the three named targets - message sends and widget
handshakes, the only two that exist as real endpoints today; file-upload initiation follows the
same pattern once Stage 5's presigned-upload flow (`file-storage.md`) exists, not before.
`IRateLimiter`/`RateLimitKey`/`RateLimitRule`/`RateLimitDecision` live in
`Ago.Platform.Abstractions`, `RedisRateLimiter` in `Ago.Platform.Caching.Redis` alongside
`RedisCache` - same technology, same project, sharing its `IConnectionMultiplexer` and
`ResiliencePipeline`. The Lua script reads time from Redis's own `TIME` command, not the caller's
clock - two `Ago.Chat.Api`/`Ago.Chat.Worker` replicas racing the same bucket must agree on how much
time has passed, and their own clocks can disagree. A failed check (Redis unreachable) fails open
(`Allowed: true`) rather than throwing or denying - `adr/0009` already named this: "a counter whose
loss is acceptable (rate limits fail open to the next window)."

`SendVisitorMessageHandler` checks per-visitor first (cheapest, no database work yet), then
per-site once the conversation load has revealed which site. `POST /api/v1/visitor-sessions` checks
per-site only, keyed by the public key itself, before the site lookup - there is no visitor id yet,
that is what the endpoint is about to mint. A denied hub-method send throws `HubException` (a hub
cannot return an HTTP status); a denied handshake returns `429` with a `Retry-After` header. Bucket
capacity/refill defaults are hardcoded in configuration (`MessageSendRateLimitOptions`,
`VisitorSessionRateLimitOptions`) - a starting point, not measured or load-tested, per-site
overrides deferred until an admin API exists to set them.

Ingress-level rate limiting also exists (`overview.md`) but is a blunt instrument: it protects the
cluster, while this protects a tenant.

## Failure behaviour

Every cache call is wrapped so that a Redis outage means "cache miss", never an error surfaced to a
user. The circuit-breaker lives in the adapter (`Infrastructure`), never in the use case. Cache hit
ratio, latency, and breaker state are exported as metrics from day one; a cache without a hit-ratio
metric is a guess.

**Shipped in `3-04`**: a single Polly `ResiliencePipeline` (a fixed, short timeout plus a circuit
breaker - values deliberately conservative and unmeasured, a placeholder for Stage 7's load test to
tune, not a benchmarked number) wraps every Redis-touching call in `RedisCache`, and every one of
those calls chains `.WaitAsync(cancellationToken)` on top - without it, Polly's timeout has nothing
to actually cancel, since StackExchange.Redis's async API takes no `CancellationToken` of its own,
and a call against an unreachable Redis can run far past the configured timeout regardless of what
Polly says (found by running the container-failure test for real - `RedisConnectionRegistry`, 3-01,
already does the same `.WaitAsync` for the same reason). `RedisCacheContainerFailureTests` (platform)
and `SiteConfigCachingContainerFailureTests` (product) stop a real Redis container mid-test and
assert reads still succeed, correct but slower, rather than throwing - `adr/0009`'s "`FLUSHALL` is
survivable" claim, exercised for real rather than a thought experiment. The Redis circuit breaker
stays inline inside `Ago.Platform.Caching.Redis` rather than a new `Ago.Platform.Resilience`
project - one caller does not justify extracting a shared library `naming-and-structure.md` already
reserves the name for (the webhook dispatcher, a later stage, per `adr/0013`); that extraction is a
`git mv` and a namespace change when a second caller shows up, not a redesign.
