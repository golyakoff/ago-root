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

`ICache` is declared in `Application/Abstractions` and implemented in
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

| Data | TTL | Invalidation | Why it is cacheable |
|---|---|---|---|
| Site config (`public_key`, allowed origins, widget settings) | 5 min + jitter | Event `SiteSettingsChanged` | Read on every widget handshake, changed rarely. This is the hot one. |
| Operator profile + capacity | 1 min | Event on change | Read on every assignment decision |
| Conversation metadata (participants, state) | 30 s | Event `ConversationAssigned` / `ConversationClosed` | Read on every inbound message |
| Recent message page (last N of a conversation) | 15 s | Write-through on new message | Reconnect storms re-request the same page |
| Visitor token validation result | 2 min | TTL only | Pure function of a row that never changes |

**Never cached**: anything used to make a write-side consistency decision. The assignment engine
reads `active_chats` from the database inside its transaction, never from Redis, because the whole
point of that path is an atomic check-and-increment (`concurrency.md`). Caching a value you then
compare-and-set is how portfolio projects quietly grow race conditions.

## Patterns we implement

- **Cache-aside** as the default. Read cache, miss, load, populate, return.
- **Stampede protection.** A miss on a hot key must not hit the database N times. Single-flight
  in-process (`ConcurrentDictionary<string, Lazy<Task<T>>>`) plus a short Redis lock for the
  cross-node case. Worth a load test: cold cache + 1000 concurrent readers.
- **TTL jitter.** Every TTL gets +/- 10% randomisation so that entries created together do not
  expire together and synchronise a thundering herd.
- **Event-driven invalidation.** Invalidation messages travel over the broker, so all nodes drop the
  key. This is a real use of the messaging layer, not a second-class path: `CacheInvalidated` is a
  normal integration event with the same at-least-once semantics.
- **Negative caching** for "site not found" lookups, with a short TTL, so a bad script tag on a
  popular page cannot hammer the database.
- **Two-level cache (Stage 7, measured).** In-process `MemoryCache` in front of Redis for site
  config. Only added if the load test shows Redis round-trips in the hot path; the accompanying
  cost is a bounded staleness window that must be written down, not discovered later.

## Rate limiting and counters

Per-site and per-visitor limits on message sends, widget handshakes, and file uploads. Implemented
as a token bucket in a Redis Lua script (atomic check-and-decrement in one round trip) behind an
`IRateLimiter` port. Application code asks "may this visitor send?" and gets a decision plus a
retry-after; it never knows Redis exists.

Ingress-level rate limiting also exists (`overview.md`) but is a blunt instrument: it protects the
cluster, while this protects a tenant.

## Failure behaviour

Every cache call is wrapped so that a Redis outage means "cache miss", never an error surfaced to a
user. The circuit-breaker lives in the adapter (`Infrastructure`), never in the use case. Cache hit
ratio, latency, and breaker state are exported as metrics from day one; a cache without a hit-ratio
metric is a guess.
