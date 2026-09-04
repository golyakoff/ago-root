# who held which conversation, from when to when, and how it came about

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing
- **Decision**: `docs/design/decisions.md` §2, the *store ownership intervals, not counters*
  amendment (2026-09-04)

## Goal

The system keeps an append-only record of every assignment: which operator held which conversation,
from when to when, and how it came about. Nothing derived is stored; everything derived is a query.

Today `Conversation.OperatorId` is a single nullable field and a transfer overwrites it, so the past
is erased at the moment it becomes interesting. That is the **only** missing raw data: message
timestamps (`Message.CreatedAt`, `Message.Sequence`) and `Conversation.CreatedAt`/`ClosedAt` already
exist, so response times, longest pauses and the distribution of pauses by length are all already
computable. The assignment timeline is not.

## Why an interval and not a counter

§2's amendment, and the reasoning is the item's whole justification. An operator who takes work
beyond capacity trades a better *concurrency* figure for a worse *response-time* one, and over the
two the trade roughly balances — but a daily average cannot show that trade: *slow because they were
running seven at once* and *slow for no reason* are identical in it. The author's own constraint —
that one more chat should cost seconds rather than a quarter of an hour — is uncheckable without
knowing the load at the moment.

**Concurrency at any instant is an interval overlap.** That is the query these rows exist to make
possible, and it is why the counter on `operators` (`active_chats`, which stays exactly as it is)
cannot substitute: it holds a present number and no history.

## Cost, stated rather than assumed

One or two rows per conversation, against dozens of messages. This is not a data-collection project.

## Context to read first

- `docs/design/decisions.md` §2 in full, both amendments
- `docs/architecture/data-model.md` — where an append-only table goes, and why this one is **not**
  partitioned the way `messages` is (`adr/0087`): its row count is per conversation, not per message
- `docs/architecture/caching.md` and `CLAUDE.md` rule 8 — no write decision reads this table, which
  is what keeps it a read concern
- `docs/architecture/concurrency.md`, "Operator assignment: the contended path"
- `Ago.Chat.Domain/Conversation.cs` (`AssignTo`, `ClosedAt`),
  `Ago.Chat.Application/UseCases/AssignConversation/AssignConversationHandler.cs`,
  `Ago.Chat.Application/UseCases/TransferConversation/TransferConversationHandler.cs`,
  `Ago.Chat.Worker/SkipLockedAssignmentClaimer.cs`, `Ago.Chat.Worker/RedisLockAssignmentClaimer.cs`,
  `OperatorConversationReleaser` (`4-04`)
- `docs/conventions/date-and-time.md` — every instant here is a `DateTimeOffset` from `IClock`

## Scope

- **`conversation_assignments`**: `id`, `site_id`, `conversation_id`, `operator_id`, `started_at`,
  `ended_at` (nullable), `source`. Append-only: a row is inserted when an operator starts holding a
  conversation and stamped with `ended_at` when they stop. Nothing else ever updates it.
- **`source`** is the provenance: `Assigned` (either claimer), `Transferred`
  (`TransferConversationHandler`), and — added by the items that create those paths — `Taken`
  (`23-04`) and `Additional` (`23-05`). The two that exist today are written by this item.
  **The stored value is a raw fact and no screen prints it verbatim**; see the naming note below.
- **Every writer, or the table lies.** The two claimers, `AssignConversationHandler`,
  `TransferConversationHandler` (which closes one interval and opens another in the same
  transaction), `CloseConversationHandler` and `OperatorConversationReleaser` (both of which close an
  interval without opening one). A writer that forgets leaves an interval open forever, and an open
  interval is indistinguishable from a live one — which is why the done-when list asserts each path
  rather than sampling.
- **A reconnect is not a new interval.** `OperatorHub.JoinConversationAsync` calls
  `AssignConversationHandler` on every join, and `Conversation.AssignTo`'s same-operator no-op
  returns before doing anything. The interval writer sits behind that no-op, never in front of it.
- **The port**: `IConversationAssignmentLog` in `Application/Abstractions`, implemented in
  `Infrastructure.Postgres`. The two claimers are raw SQL and already own their own connection and
  transaction, so they write the row inside their existing statement's transaction rather than
  through the port — say so in the code, because splitting the two would let a claim commit without
  its interval. The dependency rule is why the interface lives in Application at all: the handlers
  must not know Npgsql, and the alternative — passing a `DbContext` into the use case — would make
  every assignment test need a database.
- **No aggregates and no read model.** §2 is explicit: interval overlap gets expensive at scale, and
  that is a read concern to solve when a report is measurably slow, not in anticipation. Any claim
  that it is slow needs a run in `load/` (`CLAUDE.md` rule 7).
- `docs/architecture/data-model.md` gains the table. `docs/architecture/personal-data.md` gains §2's
  own distinction — **timestamps are not personal data, message content is** — and the consequence
  it protects: erasing a conversation need not take last month's numbers with it. Whether `16-02`'s
  conversation erasure drains this table is a decision the item makes and records; the rows name an
  operator and a conversation and hold no content.

## Naming, and what a report may print

§2's second amendment: **"forced" is a bad label for a screen a person is judged on.** The two kinds
a reader sees are a **standard** conversation and an **additional** one, where *additional* means one
held while the operator was already at or past their capacity — computable from these rows' own
overlap against `operators.capacity`, not a stored flag. This item stores the raw fact and computes
nothing; the rule is written here so the first reader of these rows does not invent a third
vocabulary. `23-17` is where it is rendered.

## Out of scope

- Any report, screen or aggregate over the intervals — `23-17` and `23-18`.
- Changing what `active_chats` is or does. It stays the denormalised counter `IOperatorCapacity`'s
  compare-and-set compares against; this table never participates in a write decision.
- Backfilling. `Conversation.OperatorId` gives at most the *current* holder with no start time, so a
  backfill would manufacture intervals nobody observed. The table starts empty — the same "null means
  it predates the column" shape `Conversation.ClosedAt` already establishes.
- A domain or integration event per assignment. Nothing consumes one, and adding it now would be a
  contract to version for no caller (`messaging.md`).

## Done when

- [ ] Each of the six writers opens or closes exactly the interval it should, asserted per path —
      including that `CloseConversationHandler` and `OperatorConversationReleaser` close without
      opening.
- [ ] A transfer leaves two rows: the first with an `ended_at`, the second open, and they do not
      overlap beyond the transaction's own instant.
- [ ] A hub reconnect by the same operator adds no row.
- [ ] Two `Worker` replicas racing one conversation produce exactly one assignment **and** exactly
      one interval — the concurrency test `4-02` already has, extended.
- [ ] A conversation closed while held leaves no open interval.
- [ ] An overlap query answers "how many did this operator hold at instant T" against a fixture with
      a known answer. It is written in this item even though no screen calls it yet, because it is
      the only proof the rows are shaped for their purpose.
- [ ] `data-model.md` carries the table; `personal-data.md` carries the timestamps-versus-content
      distinction and this table's own erasure answer.

## Open questions

None.
