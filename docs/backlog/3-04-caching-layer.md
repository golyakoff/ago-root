# Caching layer: ICache, cache-aside for site config, stampede protection

- **Stage**: 3
- **Status**: done
- **Depends on**: `3-01-connection-registry.md`, loosely - reuses the `IConnectionMultiplexer`
  registration `3-01` introduces rather than opening a second Redis connection. No functional
  dependency otherwise; can be built in parallel with `3-02`/`3-03` once `3-01` merges.

## Goal

`ICache` exists as a port, implemented against Redis, with the first real cached read wired up:
site config on the widget handshake path - `caching.md` names this "the hot one." Stampede
protection and TTL jitter are real, not asserted. Losing Redis degrades this path (cache miss,
slower, correct) rather than corrupting or erroring it (`adr/0009`).

## Context to read first

`docs/architecture/caching.md` in full (the port shape, the "what we cache and why" table, the
patterns section), `adr/0009`, `docs/architecture/resilience.md`'s Redis row specifically (timeout +
circuit breaker + fallback-to-miss).

## Scope

- `ICache` in `Ago.Platform.Abstractions`, exactly the shape `caching.md` specifies:
  `GetAsync`/`SetAsync`/`GetOrCreateAsync`/`RemoveAsync`, `CacheKey`, `CacheEntryOptions`. Not
  `IDistributedCache` - the doc already explains why.
- `Ago.Platform.Caching.Redis`: the implementation. `GetOrCreateAsync` does real stampede
  protection - in-process single-flight (`ConcurrentDictionary<string, Lazy<Task<T>>>`) plus a
  short Redis lock for the cross-node case, per `caching.md`'s Patterns section.
- TTL jitter (+/- 10%) applied uniformly, not per call site.
- First real call site: site config lookup (`public_key`, `allowed_origins`, widget settings) on
  whatever currently loads it per request - wrap it in `GetOrCreateAsync`, 5 min TTL + jitter.
- Event-driven invalidation: a `SiteSettingsChanged` integration event (new, in `Ago.Chat.Contracts`
  - product-specific, since it names a site) triggers `CacheInvalidated` (the platform-generic
  broadcast event `messaging.md`'s Topics table already names, `Broadcast` mode so every node
  drops the key, not just one).
- Negative caching for "site not found," short TTL, per `caching.md`.
- Resilience at this boundary: short timeout, circuit breaker, fallback to cache miss on any Redis
  failure - never surface an error to a caller (`resilience.md`). See Open questions for where this
  code should live.

## Out of scope

- Operator profile/capacity caching, conversation metadata caching, recent-message-page caching -
  `caching.md`'s table names five things to cache; this slice ships the first (site config, "the
  hot one") end to end, proven, rather than five shallow ones. Add the others as their own small
  slices once this shape is proven, following the same pattern.
- The two-level (in-process `MemoryCache` in front of Redis) cache - `caching.md` is explicit this
  is Stage 7, measured, not assumed.
- `IRateLimiter` - `3-05`, even though it is also Redis-backed and lives in the same project.

## Done when

- [x] `Ago.Chat.Integration.Tests` (real Redis via Testcontainers): a cache miss populates from
      Postgres and returns the value; a subsequent read within the TTL never touches Postgres
      (assert this, not just assume it from timing). `SiteConfigCachingTests`, with a counting
      decorator around the real `SiteRepository` as the assertion, not a timing assumption - covers
      both the positive hit and the negative-cache ("site not found") case.
- [x] A concurrency test: N concurrent readers against a cold key each get the correct value, and
      the backing store is hit once, not N times - the stampede-protection claim, proven under
      actual concurrency (`Ago.Chat.Concurrency.Tests`, matching how `2-05`/`2-06` proved their own
      concurrency claims rather than asserting them). `SiteConfigCachingStampedeTests` - 30
      concurrent readers, one Postgres hit. The platform-level primitive gets its own proof too,
      one layer down: `Ago.Platform.Integration.Tests.RedisCacheTests` (in-process single-flight)
      and `CacheInvalidationTests` (the broadcast plumbing, real Redis + real RabbitMQ).
- [x] A test that stops the Redis container mid-test and confirms reads still succeed (as cache
      misses, correct but slower) rather than throwing - the `adr/0009` "FLUSHALL is survivable"
      claim, exercised for real, not a thought experiment. `RedisCacheContainerFailureTests`
      (platform) and `SiteConfigCachingContainerFailureTests` (product). Found and fixed a real bug
      writing these: every Redis-touching call in `RedisCache` needed an explicit
      `.WaitAsync(cancellationToken)` chained on top of Polly's own timeout, or a call against an
      unreachable Redis ran ~20s instead of a fraction of a second - `RedisConnectionRegistry`
      (`3-01`) already did this for the same reason, missed when writing this slice's own calls.
- [x] `docs/architecture/caching.md` gets the "shipped" treatment for the pieces this slice covers,
      leaving the rest explicitly forward-looking (the same pattern `data-model.md` uses for
      partially-shipped sections).

## Open questions

None. **Resolved**: the Redis circuit breaker stays inline inside `Ago.Platform.Caching.Redis` (a
single Polly policy, no new project) rather than standing up `Ago.Platform.Resilience` now.
`naming-and-structure.md` already reserves that project name for when the webhook dispatcher
(`adr/0013`, a later stage) becomes a second real caller needing the same patterns - extracting a
shared library at that point is a `git mv` and a namespace change, not a redesign, and building it
now from exactly one caller would be a guess about the second one (`clean-architecture.md`'s
qualifying rule).

## Note for a future session

`SiteSettingsChanged` (`Ago.Chat.Contracts`) has no producer yet - nothing changes a site's settings
today, site administration is Stage 5. `SiteCacheInvalidationConsumer` is written and tested against
the contract directly so invalidation already works the day a real producer exists, the same
"documented, not yet wired" status `realtime.md`'s `clientMessageId` has. `GetSiteByPublicKeyHandler`
was renamed to `GetSiteConfigByPublicKeyHandler` (command record too) before it ever compiled clean -
a test file under `UseCases/GetSiteByPublicKey/` whose own namespace ends in `.GetSiteByPublicKey`
shadowed the plain name; the folder/namespace stayed `GetSiteByPublicKey`, only the type got the more
specific name (`RecordUnread`/`RecordUnreadMessage`'s own precedent).
