# Reconnect and resume: pick up from the last known sequence

- **Stage**: 3
- **Status**: ready
- **Depends on**: `3-02-targeted-fanout-delivery.md` (the meaningful case to prove - "did we lose a
  message" - is a reconnect that crosses nodes, which needs fan-out to be real first)

## Goal

A client that reconnects after a drop (network blip, rolling deploy, node death) tells the server
its last known `sequence` per open conversation and receives exactly the delta, never a full
replay and never a gap (`realtime.md`'s Client protocol section). The client backs off with
jittered exponential delay rather than reconnecting in a tight loop.

## Context to read first

`docs/architecture/realtime.md`'s Client protocol section, `docs/conventions/date-and-time.md`
(ordering is by `sequence`, never by time), `edge.md`'s Rolling deploys section (why jitter matters
- "a rolling restart becomes a self-inflicted thundering herd" without it).

## Scope

- `VisitorHub.JoinAsync`/`OperatorHub`'s equivalent accept an optional last-known `sequence` per
  conversation (today `JoinAsync` always returns a full first page via `GetHistoryAsync` with
  `BeforeSequence: null` - extend it, do not duplicate it: `GetConversationHistoryHandler` already
  paginates by sequence, so "the delta since sequence N" is the same query with a different cursor
  direction, not a new handler).
- Server-side: no state to reconstruct beyond what's already in Postgres - `messages.sequence` is
  already the source of truth `2-06`'s partitioning did not disturb.
- Client-side backoff: since the real widget does not exist until Stage 5
  (`docs/roadmap.md`), this is proven against `Ago.Chat.Api/wwwroot/dev-harness.html` (the existing
  `1-06` manual-verification harness) - extend it with a minimal reconnect loop (exponential +
  jitter) rather than building throwaway client code that will not survive to Stage 5 anyway. State
  plainly in the PR that this is a manual-harness proof of the protocol, not the production
  reconnect UX.
- Server may proactively tell a client to reconnect before shutdown (`realtime.md`: "Server may
  send `reconnect(after: jitteredDelay)`") - stub the hub method now even if nothing calls it yet;
  `3-06` (graceful shutdown) is the real caller.

## Out of scope

- The production widget's reconnect implementation - Stage 5.
- Reconnect-storm load testing (jitter's actual effectiveness under load) - Stage 7, per
  `edge.md`'s own note that this is "a scenario in the Stage 7 load test," not asserted here without
  a number.

## Done when

- [ ] `Ago.Chat.Integration.Tests`: a client joins, receives messages 1-5, "reconnects" (a fresh hub
      connection) passing `lastKnownSequence: 3`, receives exactly messages 4-5 - no gap, no
      duplicate, no full replay.
- [ ] `Ago.Chat.Concurrency.Tests`: a message sent while a client is disconnected (registry entry
      expired, per `3-01`) is still delivered in full on the next reconnect via history, not lost -
      the "does not need the fan-out path to still arrive eventually" case.
- [ ] `dev-harness.html` demonstrably reconnects with visible jittered backoff (manual verification,
      recorded the way `1-06`'s manual SignalR verification was - what was actually run, not
      "should work").
- [ ] `docs/architecture/realtime.md`'s Client protocol section gets the "shipped" treatment.

## Open questions

None.
