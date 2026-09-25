# 26-138 · [chat] Don't re-assign an inactivity-released conversation until new activity (churn root fix)

- **Stage**: 26 — the root-cause fix for the 5-minute push churn (`26-83`), beyond Fix A (`26-119`) and
  Fix C (`26-120`). Found by the 26-83 push re-analysis, 2026-09-25.
- **Status**: ready.
- **Depends on**: `26-119` (Fix A, landed). Complements `26-120` (Fix C — dedup hides the buzzing; this
  stops the churn at source so the DB/assignment/realtime work stops too).

## Why
`AutoCloseInactiveConversationsJob` (5-min interval) releases an idle widget conversation `Assigned→Waiting`;
`ConversationAssignmentJob` re-claims it → assignment/waiting push → next cycle repeats. Fix A only blocks
re-claim when the **last message is the operator's**. A conversation whose last message is an **unanswered
visitor message** that then went idle still satisfies Fix A's predicate, so it is released and re-claimed
every 5 minutes — the residual storm the operator still sees on a build that already has Fix A.

## Author direction (2026-09-25)
Releasing an idle conversation back to the free slot pool (`Assigned→Waiting`) is **intended and good** — keep
it. The bug is the **automatic re-assignment back**. Two changes:
1. **Raise `AutoCloseInactiveConversationsJob` interval 5 min → 15 min** (less frequent churn regardless).
2. **Once released to Waiting, never auto-reassign it back — only if a visitor message arrived after the
   release.**

## The one promise
A conversation released by the inactivity job is **not re-assigned until a visitor message arrives after the
release point** — so an idle, already-seen conversation stays in Waiting (freeing the slot, as intended) and
stops churning `Assigned↔Waiting`/pushing, while a genuinely new visitor message still gets it assigned and
pushed. The job runs every 15 minutes.

## Scope (confirm exact shape against the code)
- **Interval**: `AutoCloseInactiveConversationsJobOptions.Interval` 5 min → **15 min**.
- Record a **release marker** when `AutoCloseInactiveConversationsJob` releases a conversation — e.g. the
  server `sequence` at release time (a column on the conversation / a small marker), so "activity since
  release" is expressible.
- `WaitingConversationClaimQuery` (Fix A's predicate) additionally requires the latest visitor message's
  `sequence` to be **greater than the release marker** — a real post-release visitor message, not merely
  "last message authored by Visitor". A released-and-untouched conversation is therefore never re-claimed.
- Likely one EF **migration** (the release marker column) → migration lane, one at a time.
- Must not strand a genuinely-waiting conversation: it still auto-closes at the existing `WidgetCloseWindow`.

## Done when
- [ ] An unanswered-then-idle widget conversation is released once and **not** re-assigned/pushed on the next
      cycles (no 5-min churn); a new visitor message after release re-assigns + pushes normally.
- [ ] Migration applies cleanly; `Ago.Chat.*` suites green (per-project counts); fails-before evidence for the
      "unanswered-idle no longer re-claims" case.
