# 26-119 · [chat] Do not re-assign an idle conversation that has no pending visitor message (fix A for the 5-min push storm)

- **Stage**: 26 — fix **A** for `26-83` (root cause diagnosed 2026-09-25, author chose A+C).
- **Status**: done — merged as `ago-chat#364` (26-83 fix A: assignment only claims a Waiting conversation whose latest message is from the Visitor; both claimers; no migration).
- **Depends on**: nothing.

## The root cause (confirmed live on the stand)

Push notifications go out in a batch **every exactly 5 minutes** (~45 sends/cycle across tenants), not per
message — an operator gets a batch equal to their assigned/idle conversations. The 5-minute source is
`AutoCloseInactiveConversationsJob` (`Interval` = 5 min). Its release pass
(`ReleaseStaleAssignedWidgetBatchAsync`, `25-118`) moves an idle-but-not-yet-old widget conversation
(past `WidgetInactivityWindow`, before `WidgetCloseWindow`) from `Assigned` back to `Waiting` to free the
operator's slot. Then `ConversationAssignmentJob` re-assigns any `Waiting` conversation
(`WaitingConversationClaimQuery` picks Waiting rows **regardless of whether anything is actually awaiting a
reply**), which fires an assignment/waiting push. Next cycle the conversation is still idle → released →
re-assigned → pushed again. The conversation churns `Assigned↔Waiting` every 5 min and pushes each time.

## Fix A — break the churn at assignment

**The assignment job must not (re-)assign a `Waiting` conversation that has nothing actually awaiting an
operator** — i.e. a conversation whose latest activity is not an unanswered inbound visitor message. An
idle conversation released for inactivity (visitor silent) has no pending inbound, so it must **stay
`Waiting`** (and eventually auto-close at `WidgetCloseWindow`) rather than be immediately re-assigned.

- Change `WaitingConversationClaimQuery` (and/or the claimer's candidate selection) so a `Waiting`
  conversation is assignable **only when it has a pending/unanswered inbound visitor message** (define the
  predicate precisely against the schema — e.g. the last message is inbound and the conversation is not
  already answered/handled; confirm against how "unread"/"last message direction" is represented).
- A genuinely-waiting conversation (visitor wrote, nobody has replied) still gets assigned exactly as
  today, so no regression to the real queue.
- When a new visitor message arrives on an idle conversation, it becomes assignable again immediately
  (the new inbound is the signal).
- Do NOT change the auto-release/auto-close windows themselves (that was rejected option D); this fixes the
  re-assignment side, which is what turns a one-time release into a perpetual loop.

## Out of scope

- The push-dedup safety net (that is fix **C**, `26-120`).
- Changing `AutoCloseInactiveConversationsJob`'s release/close passes.
- Any Android change.

## Done when

- [x] An idle conversation released for inactivity is **not** re-assigned while no new visitor message is
      pending; it stays `Waiting` (and auto-closes at its window). A conversation with a pending inbound
      message is still assigned exactly as before.
- [x] A test proves: released-idle → not re-claimed next cycle; new inbound → claimable again.
- [x] `dotnet format` / build (0 warnings) / full suite green, counts reported. No migration expected;
      say so (or route via the migration lane if one is genuinely needed).
