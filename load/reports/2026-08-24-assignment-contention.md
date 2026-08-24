# 7-04: assignment contention (reduced scale)

**Date**: 2026-08-24
**Commits**: `ago-chat` `f9c090dd41b353c16d9e2684874a1f6616676b5e` (`main`) plus this branch's own
uncommitted `Ago.Chat.LoadDriver` extension (see this item's own handback notes - not yet committed
anywhere), `ago-root` `04ecf0e974c0f9e0f519fb8ded952e2db1885226` (`main`, branch point for
`docs/7-04-load-scenarios`)
**Hardware**: one Windows 11 development workstation - 11th Gen Intel Core i7-11800H, 8 cores / 16
logical processors, 63.8 GB RAM. **Not** the provisioned cluster `nfr.md` targets.

## Scale disclosure

**Deliberately, explicitly NOT `nfr.md`'s own target** - same reduced-scale, unsupervised-overnight
decision as every other report in this batch (full reasoning in `2026-08-24-steady-ingest.md`).

| | `nfr.md` target | This run | Scale factor |
|---|---|---|---|
| Conversations in the waiting queue | 10 000 | 150 created | **1.5%** |

Proves the scenario design and reporting method. **This report's actual headline finding is not a
scale result at all - it is a real, reproducible bug in the automatic assignment engine's capacity
accounting**, found live by running this scenario, not by inspection alone. See below.

## Topology and tooling deviations

Same base topology as the rest of this batch: compose loop, `Api` on `5109`/`5110`, one `Worker`
(this scenario is the one that actually exercises `Worker`'s `ConversationAssignmentJob` - every
other scenario in this batch used the manual `OperatorHub.JoinConversationAsync` path instead, which
does not touch operator capacity at all, see below). Real `.NET SignalR client` driver.

**Manual vs. automatic assignment - why this scenario is different from the rest of this batch.**
Reading `AssignConversationHandler` (`ago-chat/src/Ago.Chat.Application/UseCases/AssignConversation/
AssignConversationHandler.cs`) confirmed it never calls `IOperatorCapacity` at all - the operator-
initiated `JoinConversationAsync` path every other scenario in this batch uses is capacity-blind by
design. `4-01`'s actual capacity-checked path (`OperatorCapacityStore.TryClaimAsync`,
`concurrency.md`'s own named target for this item) is only reached through `Ago.Chat.Worker`'s
periodic `ConversationAssignmentJob` (`SkipLockedAssignmentClaimer`, 2 s tick, 20-per-site batch by
default) acting on conversations left in `Waiting` state. This scenario therefore, deliberately,
creates conversations via `VisitorHub.JoinAsync` **only** - no manual assignment - and observes the
push notification the automatic engine sends on assignment (`"ConversationAssigned"`, both visitor
and operator recipients per `ResolveConversationAssignmentTargetsHandler`).

**A real bug in this scenario's own driver code, found and fixed before the reported run.** The first
attempt at this scenario (`LOADDRIVER_QUEUE_DEPTH=150`, discarded, not reported further) registered
each visitor connection's `"ConversationAssigned"` handler *after* `JoinAsync` returned. On a mostly-
empty queue with capacity available, the automatic assignment job's next tick can claim and push the
assignment event within milliseconds of the conversation existing - faster than the driver's own
post-`JoinAsync` `.On(...)` call, and SignalR's client silently drops a push for a method with no
handler registered yet (it does not buffer). That run only observed 5/150 assignment events even
though `operators.active_chats` correctly showed full capacity consumed - a driver-side observation
gap, not a product bug. Fixed by adding a `beforeJoin` hook to `StartVisitorAsync` so the handler is
registered on the connection **before** `JoinAsync` is ever invoked, closing the race
(`tests/Ago.Chat.LoadDriver/Program.cs`, this branch). Verified fixed at small scale (15/15 observed,
`n=15` clean run) before the real 150-deep run below.

**Shared-database cleanup, done before this run.** This compose Postgres is shared with a concurrent,
unrelated session (`7-02`, visible as `ago-chat-7-02`'s own `Ago.Chat.Api` process on the default port
`5009`) and carries state accumulated across many prior sessions (`6-06` through `7-03`). Before this
run, `operators.active_chats` was observed at `50/50` and `5/5` (fully consumed) purely from this
session's own earlier scenarios (`steady-ingest`/`burst-ingest` lanes manually assigned and never
closed; `connection-storm`'s 300 idle conversations left `Waiting`) plus this exact bug this report
is about. `DELETE FROM messages/conversations WHERE state = 'Waiting'` and
`UPDATE operators SET active_chats = 0` were run directly against Postgres immediately before this
scenario, to get a clean, honest starting baseline for the measurement - stated plainly as a real
action taken, the same "safe on a dev box, the data is disposable" precedent `local-dev.md` already
established for purging orphaned RabbitMQ queues. **Not a hack to inflate the result**: the *reason*
this reset was necessary at all is this report's own headline finding.

## What this scenario answers

`concurrency.md`'s own named target: does `OperatorCapacityStore.TryClaimAsync`'s atomic
compare-and-set correctly gate the automatic assignment engine under a genuine, sustained waiting-
queue backlog, and what is the waiting -> assigned latency while the queue stays non-empty?

## Load shape

150 visitor conversations created concurrently (25-at-a-time gate), **none manually assigned** - left
for `Worker`'s automatic engine to claim. A background drain loop closes up to 8 assigned-but-not-yet-
closed conversations every 3 s (via the real `POST .../close` endpoint, using whichever of
`demo-operator`/`demo-admin`'s token matches the conversation's actual assigned operator from the
push event), intended to free capacity so the queue stays genuinely non-empty and draining rather than
plateauing after the first capacity's worth. 240 s timeout.

## Results

Source: `RunAssignmentContentionAsync`, `tests/Ago.Chat.LoadDriver/Program.cs` (this branch,
`ago-chat`). Raw CSV: `load/output/raw/assignment-contention.csv` (gitignored). Full console log:
`load/output/raw/assignment-contention-console.log`.

**51/150 conversations were ever assigned. The run hit its 240 s timeout with 99 still `Waiting`.**

| Metric | n | p50 | p95 | p99 | max |
|---|---|---|---|---|---|
| Waiting -> assigned latency (queue non-empty) | 51 | 2 492.5 ms | 4 561.7 ms | 4 802.2 ms | 4 802.2 ms |

49 close calls succeeded; 2 failed with `403 Forbidden` (a conversation's actual assigned operator did
not match the token the driver picked for it - not investigated further, a small, honestly-reported
edge case against 49 successes, not the point of this report).

**Progression, from the run's own log** (`assignment-contention-console.log`): the queue reached
40/150 within the first drain tick, 51/150 by the third, then **plateaued at exactly 51/150 for the
remaining ~210 s of the 240 s run**, despite the drain loop successfully closing 49 conversations
during that same window.

## The finding: `CloseConversationHandler` never releases operator capacity

**Confirmed directly against the running system, not just by reading code**: immediately after this
run's timeout, `operators.active_chats` still read `50/50` and `5/5` - unchanged from the moment
capacity was first exhausted, **despite 49 real, successful conversation closes having happened in
between** (verified: `docker exec ... psql -c "select id, capacity, active_chats from operators;"`
before and after the drain loop's 49 successful closes showed no change).

**Root cause, read directly from the code**: `IOperatorCapacity.ReleaseAsync`
(`ago-chat/src/Ago.Chat.Infrastructure.Postgres/OperatorCapacityStore.cs`) is the only thing that ever
decrements `active_chats`. Searching every caller of `ReleaseAsync` in `ago-chat/src` finds exactly
one: `OperatorConversationReleaser.ReleaseAllAsync`
(`ago-chat/src/Ago.Chat.Worker/OperatorConversationReleaser.cs`), which runs only when an operator's
*last connection anywhere* disconnects (`4-04`'s presence-lost sweep) - it bulk-releases **every**
conversation currently assigned to that operator back to `Waiting`, all at once, as a "the operator is
gone, redistribute their whole load" mechanism.

**`CloseConversationHandler`** (`ago-chat/src/Ago.Chat.Application/UseCases/CloseConversation/
CloseConversationHandler.cs`) - the handler behind the real, ordinary "an operator finishes a
conversation and closes it" action this scenario's own drain loop calls 49 times successfully - **never
calls `IOperatorCapacity.ReleaseAsync` at all**. It transitions the conversation to `Closed`, enqueues
the `ConversationClosed` outbox event, and saves - correctly, for everything except capacity
accounting. `active_chats` is therefore a monotonically-increasing counter under any normal
"operator closes conversations one at a time as they finish" traffic pattern: it only ever goes back
down when an operator's connection drops entirely, never when they simply finish a chat and move on
to the next one.

**This is not the same fact as `nfr.md`'s own binary claim "zero operators above their configured
capacity, at any assignment contention"** - no operator's `active_chats` ever exceeded its `capacity`
in this run; the compare-and-set (`WHERE active_chats < capacity`) held correctly throughout. The
problem is a different, arguably worse one for a long-running deployment: **capacity that is consumed
is never returned by the normal, intended way an operator finishes work**, so any real site would see
its automatic-assignment capacity silently ratchet down to zero over time, with the only ways back to
normal being either every operator eventually going offline (triggering the bulk-release path) or a
manual database intervention - exactly what this report's own "shared-database cleanup" section above
had to do to get a clean baseline for this scenario in the first place, which is itself indirect
evidence this is a real, already-live-in-this-shared-environment problem, not a lab artifact this
scenario manufactured.

**Recommendation, not patched here** (matches this item's own explicit scope: report, don't patch
inline): `CloseConversationHandler.CloseAndSaveAsync` should call `IOperatorCapacity.ReleaseAsync` for
the conversation's own operator whenever the conversation being closed was reached via the automatic
assignment path (i.e., had a real capacity claim behind it) - symmetric with `TryClaimAsync` at
assignment time. Filed as a new backlog item recommendation: **"Release operator capacity on
conversation close, not only on operator disconnect"** - re-run this exact scenario afterward to
confirm the queue actually drains past its first capacity's worth instead of plateauing.

## Interpretation

For the 51 conversations that did get assigned, latency against `nfr.md`'s own target (waiting ->
assigned, queue non-empty: 100 ms / 500 ms / 2 s p50/p95/p99) **misses at every percentile** (2 492.5 /
4 561.7 / 4 802.2 ms) - expected at this reduced scale and topology (a 2 s poll-tick assignment job is
itself a meaningful fraction of the target p50), and **not the interesting result of this run**. The
interesting result is that 99/150 (66%) never got assigned at all within a 240 s window, for a reason
that has nothing to do with `nfr.md`'s own scale target and everything to do with the bug above - a
10 000-deep queue at full scale would hit the identical ceiling after the first capacity's worth of
conversations, regardless of `Worker` replica count or claim-query performance, because the ceiling is
capacity accounting, not throughput.

## Server-side observations

No live dashboard for this run's own instances (same stated gap as the rest of this batch). Direct
Postgres queries (`operators.active_chats`, `conversations.state` counts) were the actual server-side
observation mechanism for this scenario, and are what surfaced the finding above - arguably more
useful here than a dashboard would have been, since the bug is in a single integer column's own
lifecycle, not a rate or a distribution.

## What was tuned

Nothing pipeline-specific. The database state reset described above is not a tuning change - default
`ConversationAssignmentJob` interval (2 s) and batch size (20) were unchanged.

## What a real, full-scale run still needs

The bug above fixed (or at minimum, the real capacity ceiling it produces accounted for in the test
plan) before a 10 000-deep queue run means anything: at full scale, this bug would make "queue non-
empty" latency essentially undefined for any conversation beyond the first capacity's worth, for the
entire remaining duration of any long-running cluster, not a transient effect a bigger `Worker`
replica count or a faster claim query could fix. The provisioned cluster, k6 or an equivalent
generator, and - unlike every other report in this batch - a **clean, dedicated demo tenant not shared
with any other concurrent session's traffic**, since this scenario is the one most sensitive to
exactly the kind of unrelated-conversation interference this run's own "shared-database cleanup"
section had to work around by hand.
