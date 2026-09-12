# 25-63 · A real-time hub for AGO Calendar, so 25-51's pending-bookings badge can be live

- **Stage**: 25
- **Status**: done — `ago-calendar#61`, `ago-console#211`
- **Verified**: 2026-09-12 — confirmed `ago-calendar` has no SignalR hub anywhere (`find ... -iname
  "*Hub.cs"` returns nothing) and `CalendarQueuePage.tsx` (the console's own pending-bookings screen)
  fetches once on mount with no live-update mechanism at all. `Ago.Chat.Api.Hubs.OperatorHub` uses
  `Ago.Platform.Realtime` for its own connection registry/scale-out — a shared platform package
  already exists to plug a second hub into, this is not starting from nothing. `ago-calendar` already
  has `Ago.Calendar.Infrastructure.Redis`, the same store `Ago.Platform.Realtime`'s own scale-out
  needs.
- **Depends on**: nothing to build against, but exists specifically to unblock `25-51`'s own "Записи"
  badge, which cannot be genuinely live without this
- **Found**: 2026-09-12, while scoping `25-51` (the left-menu unread/pending badges) — its own
  "the same real-time discipline the rest of the console already has" requirement turned out to name
  infrastructure that does not exist yet for one of the two sections it covers. The author's own
  decision, once shown the gap: build the hub now rather than settling for a poll on the calendar side.

## What is actually true

`ago-chat`'s `OperatorHub` gives the console real-time push for conversations already — new
assignments, presence, messages. `ago-calendar` has no equivalent. Every calendar screen in the
console, including the pending-bookings queue `25-51`'s own badge needs to watch, is a plain fetch
with no push channel behind it.

## Scope

- A new SignalR hub in `ago-calendar` (`Ago.Calendar.Api`), following `OperatorHub`'s own precedent:
  authenticated by the operator's JWT, scoped to a tenant, using `Ago.Platform.Realtime` for
  connection registry/scale-out rather than a bespoke mechanism — the same platform abstraction
  `ago-chat` already depends on for this, not a second implementation of the same idea.
- At minimum, one real event: a booking entering or leaving the pending state (created awaiting
  confirmation, confirmed, cancelled, or otherwise resolved) pushes to every connected operator in
  that tenant. This is the one fact `25-51`'s own badge needs; do not build a general event bus for
  every possible calendar fact as a side effect of this one push.
- The console's own `OperatorConnectionProvider`-equivalent wiring for this second hub — check whether
  the existing `realtime/operatorConnection.ts`/`OperatorConnectionProvider.tsx` can be generalized to
  a second hub connection or whether a parallel, calendar-specific connection is the more honest
  choice given they authenticate against different backends (`ago-chat` vs `ago-calendar`) — state
  which and why.

## Where this is likely to go wrong

- **Do not build this as a copy-paste of `OperatorHub` with calendar nouns substituted** — reuse
  `Ago.Platform.Realtime` genuinely, the way a second product depending on a shared platform package
  is supposed to work (`docs/architecture/repositories.md`), not two independent implementations that
  happen to look similar today and drift apart later.
- **Scope to the one event `25-51` needs.** A calendar-wide real-time system (booking edits, worker
  schedule changes, everything else `CalendarQueuePage`'s siblings could theoretically want live) is a
  much bigger, undecided piece of work — name it as a future extension if it comes up, don't build it
  now.
- **This is new infrastructure in a second product's own repository** — the same "AGO Calendar is
  additive, no edits to the platform's shape" boundary (`CLAUDE.md`, `docs/adr/0027-*`) applies: this
  adds to `ago-calendar` and consumes the existing platform package, it does not touch `ago-chat` or
  `Ago.Platform.*` itself unless a real, stated gap in `Ago.Platform.Realtime` is found along the way.

## Done when

- [x] `ago-calendar` has a real SignalR hub, authenticated and tenant-scoped, built on
      `Ago.Platform.Realtime`.
- [x] A booking entering or leaving the pending state pushes a real event to every connected operator
      in that tenant — proven by a real test, not asserted.
- [x] The console has a working connection to this hub, wired the same disciplined way
      `OperatorConnectionProvider` wires the chat one (documented reconnect/backoff behavior, not a
      bare `new HubConnectionBuilder()` with no story for a dropped connection).

## Outcome

Built by a background worker earlier in the session and landed by the managing session, independently
verified against both worktrees before committing (`land-a-slice` discipline).

**`ago-calendar#61`**: a new `CalendarOperatorHub` (`Ago.Calendar.Api/Hubs/`), authenticated and
tenant-scoped, built on `Ago.Platform.Realtime` for connection registry/scale-out — the same shared
platform package `ago-chat`'s own `OperatorHub` already depends on, not a second implementation. A
booking entering or leaving the pending state (created, confirmed, cancelled, or otherwise resolved)
pushes `BookingPendingStateChanged` to every connected operator in that tenant, via a new
`BookingPendingFanoutConsumer` in `Ago.Calendar.Worker`, driven off the existing outbox — the identical
shape `ago-chat`'s own outbox-to-hub fanout already establishes. Verified: `dotnet format
--verify-no-changes` clean; `dotnet build -c Release`, 0 warnings; `dotnet test -c Release`, 5/5
assemblies, 0 failed — Domain 229, Application 205, Architecture 26, Concurrency 26, Integration 314
(800 total, including a new end-to-end fanout test, `BookingPendingFanoutEndToEndTests.cs`).

**`ago-console#211`**: a second, calendar-specific SignalR connection
(`CalendarOperatorConnectionProvider`/`CalendarConnectionContext`) alongside the existing chat one —
kept parallel rather than generalized into one shared provider, since the two authenticate against
different backends (`ago-chat` vs `ago-calendar`) — the exact choice this item's own Scope asked to be
stated and justified. `CalendarQueuePage` now reflects a booking entering/leaving the pending state
live, without a page reload. Verified (after a rebase onto a `main` that had moved one commit ahead of
this branch's original base): `tsc -b --noEmit` clean, `eslint src ux-gate` clean, `vitest run` 121
files / 1264 tests, 0 failed, `vite build` clean (229.70 KB gzipped).
