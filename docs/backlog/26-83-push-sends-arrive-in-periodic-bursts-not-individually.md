# 26-83 · Push sends arrive in periodic bursts, not individually — root cause unknown

- **Stage**: 26
- **Status**: ready — the symptom is real and measured; the cause is not found yet
- **Found**: 2026-09-24, live on the demo stand, while investigating the author's own report of a
  slow-feeling widget-to-app message delay during real device testing.

## What is actually true today, confirmed against real logs and Postgres timestamps

Individual new messages produce fast, clean, single push sends — measured directly, not estimated:

| Message created (`messages.created_at`) | RuStore send call started | Gap |
|---|---|---|
| 08:23:15.005 | 08:23:15.057 | 52ms |
| 08:24:03.031 | 08:24:03.071 | 40ms |
| 08:24:11.607 | 08:24:11.676 | 69ms |
| 08:24:22.190 | 08:24:22.228 | 39ms |

But twice in the same test session (08:22:39–40 and 08:25:31), a burst of roughly **9–10 additional
`RuStorePushSender` HTTP calls fired within under half a second of each other**, all succeeding
(200 OK, 14–93ms each individually) — and neither burst corresponds 1:1 to a fresh message created at
that moment in the conversation being tested. The author independently reported seeing "9 notifications
arrive at once" on the real device, several for the conversation just created — matching the second
burst's timing.

**No failure, warning, or retry was logged at the application level** — `Ago.Chat.Worker`'s own logs
over a 3-hour window contain zero `fail:`/`warn:` lines related to push sending. Whatever holds these
back is invisible to this codebase's own logging, which rules out (or at least fails to confirm) an
explicit transient-failure-and-retry cycle as the visible cause — `NotifyOperatorDevicesHandler`'s own
`TransientFailure` path does log via `ChatMetrics.RecordPushSend(..., "failed")`, and nothing of the
sort was seen.

`only_operator_devices` for this operator has exactly **one** row (checked directly) — so the burst is
not device fan-out (one event, many registered devices); each of the ~10 calls in a burst is a
genuinely separate send.

## What was ruled out

- **RabbitMQ backlog** — checked before, during, and after the test window: every push-related queue
  and its `.retry` queue read `0` messages (`rabbitmqctl list_queues`) at every check. If a backlog
  existed, it drained faster than the polling interval could catch it, or it isn't sitting in a named
  queue at all.
- **Device fan-out** — one device row for the tested operator, confirmed directly.
- **An explicit failure being retried** — no failure ever logged for these calls.

## Scope

- Catch a burst *while it is forming*, not after — live `rabbitmqctl list_queues` polling at a
  sub-second interval during a deliberate test, watching every `.retry`/`.dlq` queue for the push
  topics specifically, not a snapshot before/after.
- If nothing shows up in RabbitMQ even mid-burst, the delay is somewhere *before* the broker sees these
  as separate messages — check MassTransit's/the consumer's own internal prefetch and concurrency
  settings (`ConnectionFanoutConsumerOptions`-equivalent for the push consumers), and whether the
  `Ago.Chat.Worker` process's own thread pool is being starved by something else running in the same
  process (the `MaxApiClient`/Telegram long-polling loops observed in the same logs, each holding a
  connection open for 25–30 seconds at a time, are a real candidate worth ruling in or out directly
  rather than assumed).
- Once found, decide whether the fix belongs in this repository at all, or is RuStore's own
  server-side batching (`push-notifications.md`'s own "This design makes no latency claim whatsoever" —
  if RuStore itself only delivers in bursts, no code here can change that, and the honest answer is to
  record it rather than chase a fix that doesn't exist).

## Out of scope

- `26-06`'s own real-device Done-when boxes this same session already settled (push works without
  publishing — confirmed; `docs/architecture/push-notifications.md` updated).
- The conversation-list preview not refreshing promptly — a different mechanism (SignalR operator-hub
  fan-out, not push), tracked separately as `26-84`.

## Done when

- [ ] A burst is caught mid-formation with live RabbitMQ queue polling, and the queue it is actually
      sitting in (if any) is named.
- [ ] If not sitting in a named queue, thread-pool/consumer-concurrency contention in `Ago.Chat.Worker`
      is measured and ruled in or out directly (not assumed).
- [ ] The root cause is named, or the finding "RuStore itself batches delivery" is recorded with the
      evidence for it, in `docs/architecture/push-notifications.md`.

---

## Root cause — diagnosed 2026-09-25 (live on the stand)

Pushes go out in a batch **every exactly 5 minutes** (~45 sends/cycle across tenants; an operator gets a
batch = their idle/assigned conversations), not per message. The 5-minute source is
`AutoCloseInactiveConversationsJob` (`Interval` = 5 min): its `25-118` release pass moves an idle-but-not-
old widget conversation `Assigned`→`Waiting`; `ConversationAssignmentJob` re-assigns any `Waiting`
conversation (`WaitingConversationClaimQuery` selects Waiting rows regardless of whether anything awaits a
reply) → assignment/waiting push; next cycle it is still idle → released → re-assigned → pushed again. The
conversation churns `Assigned↔Waiting` every 5 min and pushes each time. (Outbox is not the cause — it polls
every 5s with LISTEN/NOTIFY, so live delivery is instant.)

## Decision (author, 2026-09-25): fix A + C

- **A — `26-119`**: the assignment job must not re-assign a `Waiting` conversation with no pending inbound
  visitor message; idle-released conversations stay `Waiting` and auto-close, breaking the churn.
- **C — `26-120`**: dedup operator pushes per (operator, conversation) within a short window (the `26-108`
  IRateLimiter pattern), as a safety net against any other repeat-trigger.

This item stays open as the tracking parent until `26-119` and `26-120` land, then closes.
