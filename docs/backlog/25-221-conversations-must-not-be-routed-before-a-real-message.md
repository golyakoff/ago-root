# 25-221 · A conversation must not reach an operator's queue before the visitor writes

- **Stage**: 25
- **Status**: done — merged as `ago-chat#354`. Verified against real code: `ConversationState.Pending`
  exists, `Conversation.Start` sets it, `AddVisitorMessage` transitions `Pending → Waiting` keyed on
  `State` (not message count). Independently re-verified at the time: full suites green (Domain
  791/791, Application 1506/1506, Concurrency 90/90, Architecture 53/53, Integration 1510/1510) plus a
  new `WaitingConversationClaimQueryTests` (6/6) against real Postgres.
- **Found**: 2026-09-22, by the author: simply opening the widget already creates a conversation that
  gets automatically assigned to a real operator within seconds — before the visitor has typed
  anything, and even before any auto-greeting text exists. Every page load that mounts the widget
  becomes a "started" conversation an operator is expected to attend to. The author's own words: *"Пока
  клиент не написал - это не считается диалогом, на который оператор вообще должен отвлекаться, иначе
  на каждое открытие главной страницы сайта будет создаваться диалог и мы утонем в начатых диалогах."*

## What is actually true today, confirmed by tracing the real code path

`ago-widget` opens a SignalR connection the moment it mounts and immediately calls
`VisitorHub.JoinAsync`/`JoinWithTrafficSourceAsync` (`JoinCoreAsync`). That method **unconditionally**
calls `StartConversationHandler.HandleAsync`, which — if the visitor has no existing open conversation —
constructs one via `Conversation.Start` and persists it via `SaveAsync`, with **`State` set to
`ConversationState.Waiting` unconditionally**, regardless of whether a message exists.

`Ago.Chat.Worker`'s `ConversationAssignmentJob` runs on a plain interval timer (no event trigger needed)
and, every tick, finds every site with any `state = 'Waiting'` conversation and hands it to
`SkipLockedAssignmentClaimer.AssignWaitingConversationsAsync`, which claims rows via
`WaitingConversationClaimQuery` (`SELECT ... WHERE state = 'Waiting' AND blocked_at IS NULL AND
routing_suppressed_at IS NULL ... FOR UPDATE SKIP LOCKED`) and assigns each one to the least-busy
`Online` operator. **Nothing in this whole path checks whether the conversation has a single message in
it.** A widget mount that creates a brand-new conversation is, within one `ConversationAssignmentJob`
tick, a real conversation in a real operator's queue — exactly the reported symptom.

**The auto-greeting text itself is already handled correctly and needs no fix.** `23-64`/`adr/0148`'s
`Conversation.AddAutoGreetingMessage` only ever materialises the greeting *"the moment the visitor
writes — never earlier, and never for a conversation that already has a message"* (`MessageAuthorKind
.AutoGreeting`'s own doc comment). The gap is entirely about the **conversation row and its routing**,
not the greeting.

## The proposed shape — implement this unless you find a real problem, and say why

**A new `ConversationState.Pending`, ahead of `Waiting` in the state machine** — not a repurposing of
`RoutingSuppressedAt` (that flag is `23-69`/`23-77`'s permanent, restriction-only "never route this,
ever, even after messages exist" mechanism; conflating the two would risk quietly un-suppressing a
genuinely restricted visitor's conversation the first time they type — checked and confirmed this
handler's own restriction check runs *once*, at `StartConversationHandler` time, never again).

Confirmed safe and minimal by reading the actual persistence layer:

- `Conversation.State` is `HasConversion<string>()` — a plain text column, **not a native Postgres
  enum**. Adding `Pending` needs no migration.
- `Conversation.AddVisitorMessage`'s only state guard is `if (State == ConversationState.Closed)
  throw` — a `Pending` conversation is already accepted with no change to that guard.
- `Conversation.AddOperatorMessage` requires `State == Assigned` — unaffected; nothing can reach
  `Assigned` without first being claimed off the `Waiting` queue, which `Pending` never enters.
- `ConversationRepository.GetWaitingForSiteAsync`/`GetAssignedToOperatorAsync` filter explicitly on
  `State == Waiting`/`State == Assigned` — a `Pending` row is **already invisible to both, and to
  `GetOperatorQueueHandler`, with zero code changes** there.
- `ConversationAssignmentJob`'s raw SQL and `WaitingConversationClaimQuery` both filter on
  `state = 'Waiting'` literally — a `Pending` row is **already excluded from the assignment engine with
  zero changes** to either file.
- `ConversationRepository.GetActiveForVisitorAsync` matches `State != Closed` — a visitor who reopens
  the widget without ever having sent a message correctly resumes the same `Pending` conversation
  (`IsNew: false`), unaffected.

So the actual change is small and precisely targeted:

1. **`ConversationState.cs`**: add `Pending`.
2. **`Conversation.Start`**: `State = ConversationState.Pending` instead of `ConversationState.Waiting`
   — this is the *only* line that decides a brand-new conversation's starting state. Everything else
   (attachment grant seeding, `RoutingSuppressedAt` for a restricted visitor, the `ConversationStarted`
   domain event) stays exactly as it is.
3. **`Conversation.AddVisitorMessage`**: immediately after the existing participant/closed-state
   guards, if `State == ConversationState.Pending`, transition `State = ConversationState.Waiting`
   before calling into `AddMessage`. **Deliberately keyed on `State`, not on `_messages.Count`** —
   `AddAutoGreetingMessage` may have already added one message (`AuthorKind.AutoGreeting`) to this same
   conversation moments earlier inside the identical `MessageBatchWriter` transaction, and that message
   must **not** be what graduates the conversation out of `Pending`; only a real
   `MessageAuthorKind.Visitor` message may. `State` is one-directional (`Pending` only ever appears
   once, right after construction), so this check is naturally idempotent — a retried send that already
   transitioned the state on a prior attempt just finds `State != Pending` and does nothing extra.
4. **Verify, don't assume, these three things** while implementing — each is a real question this
   research pass could not fully close without running the suite:
   - Does anything downstream of `MessageAdded` (the domain event `AddVisitorMessage` raises) assume
     `State` was already `Waiting`/`Assigned` by the time it fires — e.g. an unread-counter or
     watchdog consumer that reads `conversation.State` off the same event? If so, confirm it still
     computes the right thing now that `State` has just flipped in the same call, or say what needs to
     change.
   - Does `AutoCloseInactiveConversationsJob` (or any other sweep) need to also consider `Pending`
     conversations that never receive a first message — should an abandoned `Pending` row eventually be
     closed, or is leaving it forever harmless (it costs one row, is invisible to every operator-facing
     read, and is excluded from every assignment query)? State your reasoning; don't silently add a
     sweep that wasn't asked for if leaving it alone is genuinely fine.
   - Does the widget or any hub-facing DTO (`VisitorJoinResult`, `ConversationSummaryDto`, the console's
     own rendering) branch on a conversation's `State` value anywhere in a way that would now see
     `"Pending"` where it only ever expected `"Waiting"`/`"Assigned"`/`"Closed"` — a raw string
     comparison or a switch with no default case would break silently. Check both `ago-chat` and every
     consumer (`ago-console`, `ago-widget`) that reads a conversation's state as a string.

## Out of scope

- The `23-07` funnel counter (`IWidgetActivityRecorder.RecordConversation`, fired at `JoinCoreAsync` on
  every genuinely-new conversation) — this measures "a conversation session began" as a top-of-funnel
  analytics event, a different question from "should an operator be routed to it," and nothing here
  asks to change what it counts.
- `RoutingSuppressedAt`/the restricted-visitor permanent-suppression feature (`23-69`/`23-77`/`24-10`)
  — unrelated flag, unrelated reason, untouched.
- Any change to how or when the auto-greeting text materialises — already correct (see above).

## Done when

- [x] `ConversationState.Pending` exists; `Conversation.Start` sets it unconditionally.
- [x] `Conversation.AddVisitorMessage` transitions `Pending → Waiting` keyed on `State`, confirmed by
      reading the real code (`Conversation.cs`).
- [x] A `Pending` conversation never appears in `GetOperatorQueueHandler`'s response and is never
      claimed by `SkipLockedAssignmentClaimer` — proven by `WaitingConversationClaimQueryTests` (6/6)
      against real Postgres.
- [x] The three verification questions were answered in the worker's original report.
- [x] `dotnet format --verify-no-changes`, full build, and the full test suite green — independently
      re-verified: Domain 791/791, Application 1506/1506, Concurrency 90/90, Architecture 53/53,
      Integration 1510/1510.
