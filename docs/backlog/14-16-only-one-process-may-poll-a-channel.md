# Only one process may poll a channel, and the Worker is designed to be many

- **Stage**: 14
- **Status**: ready — **decided by `adr/0089` (2026-09-02)**, which settles the mechanism the Scope
  section below deliberately left open. Read that ADR first; this item builds what it decided and does
  not re-open the choice.
- **Found**: 2026-09-02, in the live demo stand's own logs, while deploying `5f9fe37` (`15-09`).
  Not from reading the code — the symptom appeared first and the cause was traced back to it.
- **Touches**: `Ago.Chat.Infrastructure.Telegram` (`14-07`), `Ago.Chat.Infrastructure.MaxBot`
  (`14-02`), `Ago.Chat.Worker`'s hosted-service registration, `docs/architecture/concurrency.md`.

## The symptom, and why it is the smaller half

Rolling the Worker to a new image produced this, once, in the new pod:

```
Telegram API GET /bot***/getUpdates?timeout=30 -> 409 in 5663ms
Telegram long-poll for credential 01a04944-… failed; retrying.
  System.Net.Http.HttpRequestException: Response status code does not indicate success: 409 (Conflict).
```

It cleared on its own: **0** occurrences in the following 90 seconds, `getUpdates` back to `200`.
Telegram refuses a second concurrent `getUpdates` on one bot token, and during a rolling update the
old pod and the new pod are both polling. Every number in that window is a deliberate setting, none
of them wrong on its own:

| Setting | Value | Where |
|---|---|---|
| Worker `replicas` | 1 | `ago-deploy` `k8s/base/worker.yaml` |
| Deployment `strategy` | unset → Kubernetes default `RollingUpdate` | same |
| effective `maxSurge` / `maxUnavailable` | 1 / 0 (25% of 1, rounded up / down) | Kubernetes' own rounding |
| `terminationGracePeriodSeconds` | 30 | `worker.yaml` |
| `preStop` sleep | 5s | `worker.yaml` (`17-05`) |
| `LongPollTimeoutSeconds` | 30 | `TelegramBotApiOptions` |
| `ErrorBackoffSeconds` | 5 | `TelegramLongPollingServiceOptions` |

`maxUnavailable: 0` is what makes the overlap **certain rather than occasional**: the new pod must
become Ready before the old one is asked to stop, and its poller starts well before readiness. So
every single Worker rollout produces this, and always has.

**Nothing is lost and nothing is duplicated**, both checked rather than assumed:

- **No loss.** Telegram retains an update until the cursor moves past it, and `offset` only advances
  after an update has been handed to `DispatchIfMessageAsync`. An update not fetched during the
  conflict is fetched after it. The cost is *latency*, of the order of the backoff — seconds.
- **No duplicates.** `ExternalMessageId` is the idempotency key and becomes `ClientMessageId`, which
  carries a unique filtered index on `(conversation_id, client_message_id, site_id)`. Two pollers
  each holding their own in-memory cursor cannot produce two visitor messages; the database refuses
  the second.

So as a rollout symptom this is a warning-level annoyance with a real but small latency cost. It is
worth an item for the other thing it exposes.

## The actual defect: an unstated singleton inside a host documented as multi-replica

`TelegramLongPollingService` and `MaxLongPollingService` are `BackgroundService`s registered
unconditionally in `Ago.Chat.Worker/Program.cs`. Each keeps a `_pollers` dictionary of one poll loop
per active `ChannelCredential`, and each loop keeps its `offset` cursor as a **local variable** —
per-process state, never persisted, never coordinated. Both classes' own remarks explain, correctly,
why there is one loop *per bot*. Neither says anything about how many *processes* may run them, and
nothing in the code, the options, or the manifest enforces an answer.

`docs/architecture/concurrency.md` answers it the other way, explicitly:

> Multiple `Worker` replicas compete to assign waiting conversations to operators with limited
> capacity.

That is the premise of the whole "Operator assignment — the contended path" section, `SKIP LOCKED`
is chosen precisely to make it safe, and the stage-7 measurement plan names *recovery time after
killing one Api replica and one Worker replica*. The Worker is designed, documented and instrumented
as a horizontally scalable host — and two of its hosted services silently are not.

Today `replicas: 1` hides this completely. **Scaling the Worker to 2 for throughput would
permanently break inbound Telegram and MAX** — not transiently, the way a rollout does: two pollers
per bot, each terminating the other's `getUpdates`, indefinitely. The person who scales it will be
doing exactly what `concurrency.md` told them the Worker supports, and the failure will look like a
provider problem rather than a design one.

That is the failure this item exists to make impossible. It is cheap now, and it is the kind of thing
that is discovered at the worst possible moment otherwise.

## What already exists, checked before scoping

- No leader election, advisory lock, or singleton guard of any kind anywhere in `ago-chat`.
- The two poller services are structurally identical — same `_pollers` dictionary, same
  `SemaphoreSlim` gate, same refresh loop, same per-loop local `offset`. Whatever is done here is
  done once and applied to both, not twice.
- The 409 is swallowed by the generic `catch (Exception ex)` in `PollOneCredentialAsync`, logged at
  `Warning` with the same message as any other transport failure. A conflict caused by our own
  topology and a genuine Telegram outage are, today, indistinguishable in the logs.
- `MessagePartitionPruneJob` and the other Worker jobs are safe under multiple replicas by their own
  mechanisms; the pollers are the exception, not the rule.

## Scope

- ~~**Decide and record what may hold a channel poller.**~~ **Done — `adr/0089`**, which weighed the
  three shapes this section had listed and chose the first: a **session-scoped Postgres advisory lock
  keyed per `ChannelCredentialId`**, held for the life of the loop, released by the database itself
  when the holding session ends. No TTL, no renewal, takeover as the normal path.

  **The per-credential key changed what this item is.** A global poller-leader lock would have been
  simpler and confined every bot to one process forever. Keying on the credential means several Worker
  replicas *share* the bots, each holding the locks it won — so this item no longer forbids scaling
  the Worker, it is what makes the polling path scale. That is a capability, not a restriction, and
  the Done-when list below is written against it.

  Rejected in the ADR, with reasons: reusing `RedisDistributedLock` (already used in this very host by
  `RedisLockAssignmentClaimer`, and wrong here purely on *duration* — a TTL without renewal has no
  good setting for an indefinitely-held lease); a `poller_leases` table with `SKIP LOCKED` (a
  lifetime-long row lock is a lifetime-long transaction, working against autovacuum); and a fourth
  host pinned to one replica (does not even fix the rollout overlap, and discards the capability
  above).
- **Make the rollout overlap quiet, not just harmless.** Whichever mechanism wins, a poller that does
  not hold the right to poll should wait for it rather than race and log a warning.
- **Distinguish a self-inflicted 409 from a provider one** in the logs, so the next person reading
  them learns something true.
- **Correct `concurrency.md`.** Whatever is decided, that file currently tells a reader the Worker
  scales out without qualification. Either it gains the exception or the exception stops existing.

## Out of scope

- Actually scaling the Worker past one replica. This item makes that *safe to consider*; deciding to
  do it is a separate call with its own load-test evidence (rule 7).
- Persisting the `offset` cursor across restarts. It is in-memory today and that is not a defect —
  Telegram replays unacknowledged updates, which is what makes the current behaviour lossless. Worth
  naming only so a future reader does not "fix" it into a lossy optimisation.
- The other channel adapters. VK, WhatsApp, Avito, email and SMS do not long-poll.

## Done when

- [x] An ADR decides which process may poll a given channel credential, states the mechanism, and
      says plainly what happens when that process dies mid-poll. — `adr/0089`, 2026-09-02, including
      the half-open-connection case, which is bounded rather than eliminated and says so.
- [ ] Running **two** Worker instances against one active Telegram credential is proven, by test, to
      produce exactly one live poll loop — and proven to fail before the change, since that is the
      entire guarantee.
- [ ] **Two instances and two credentials distribute**: both get polled, one per instance, proving the
      per-credential key does what `adr/0089` chose it for. A mechanism that serialised every bot onto
      one process would pass every other box on this list.
- [ ] The survivor takes over when the holder stops: killing the holding instance leaves the other
      polling within a bounded, stated time. A guarantee that only works while nothing dies is not
      one.
- [ ] A rolling restart of a single-replica Worker produces **no** `409` in the logs — the observed
      symptom, gone, rather than merely explained.
- [ ] A genuine provider-side conflict is still logged, and is distinguishable from the topology one.
- [ ] `concurrency.md` no longer claims without qualification that the Worker scales out, and names
      what the exception is or that it has been removed.
- [ ] The same mechanism covers MAX, in the same change — the two services are identical and fixing
      one is how the other becomes the stale one.

## Open questions

- **Does the same reasoning reach `MessagePartitionPruneJob` and the other Worker background jobs?**
  They appear safe under multiple replicas by their own mechanisms, but "appears safe" is exactly
  what was true of the pollers until this was looked at. Worth one honest pass over every
  `AddHostedService` in `Ago.Chat.Worker`, and worth stating the result even where it is "already
  fine".
- ~~**Whether `replicas: 1` should be written down as a constraint in the manifest** in the
  meantime.~~ **Answered yes by the author, 2026-09-02, and applied** (`ago-deploy`
  `k8s/base/worker.yaml`): the comment above `replicas: 1` now says it is a constraint rather than a
  tuning knob, names the two hosted services and why two replicas break them permanently, and states
  plainly that it contradicts `concurrency.md` on purpose until this item resolves that properly. The
  rolling-update `409` is recorded there too, so the log line is not mistaken for a provider outage.

  This changes nothing about the item's scope — a comment is not a guarantee, and every Done-when box
  below stands exactly as written. It buys the item time rather than shrinking it.
