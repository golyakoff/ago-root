# 26-98 · The "Все" list cannot be read without claiming a row, and that may not be what a `site:configure` holder wants

- **Stage**: 26
- **Status**: ready — **decided (author, 2026-09-25): Option 1 — a genuine read-only view.** A
  `site:configure` holder can open a conversation from «Все» to read it without assigning it. Needs a
  server read path that opens a thread's history without `AssignTo`, plus an Android read-only ThreadScreen
  mode that disables every reply/action affordance. To be rewritten to that scope and taken (queued behind
  `26-118`, which touches the same conversation-list area).
- **Found**: 2026-09-24, landing `26-90`'s Android half (`ago-android#82`) — reported at the time, not
  silently worked around.

## What is actually true today, confirmed against the real code

`26-90` gave Android a third «Все» segment under Записи: every conversation on the site, regardless of
who holds it, gated on `site:configure` (not `conversation:read` — the item's own design pass had
already found that mismatch). The list renders — preview, count, state filter, all real. **A tap on a
row does not.**

The reason is structural, not a missing wire-up: `OperatorHub.JoinConversationAsync` **assigns before it
reads**, and `Conversation.AssignTo` accepts only a `Waiting` conversation. A tap on this admin-wide list
would, for most rows, either:

- incorrectly **claim** a conversation that is sitting in someone else's queue or already assigned to
  another operator, or
- **throw**, for one that is `Assigned` elsewhere or `Closed`.

Every other conversation list in the app (Диалоги's own queue, "Мои") is a list of things the *viewing*
operator may legitimately assign to themselves — this is the first list that is explicitly *not* that,
and the join path was never built to support "look, don't touch."

The Android side shipped with a quiet on-screen note rather than a broken tap target, which is the
honest interim answer — but it is an interim answer, not the feature.

## The question this item asks

**Should a `site:configure` holder be able to open a conversation from «Все» to read it, without
assigning it to themselves?** Three readings, each with a real cost:

1. **Yes — a genuine read-only view.** A new server capability: open a thread's history without
   `AssignTo`. Cheapest to explain to a tenant ("an administrator can see everything"), most expensive
   to build — a new endpoint/hub method, and a client-side "read-only" thread mode that disables every
   reply/action affordance `ThreadScreen` currently assumes is always available.
2. **No — «Все» stays a directory, not a way in.** The row shows what it already shows (state, preview,
   count) and nothing more; opening a conversation stays the privilege of whoever is queued for it or
   already holds it. Cheapest to build (nothing changes), but the administrator who wanted to check "what
   did we actually say to this customer" has no path to that beyond this list's own preview line.
3. **Middle ground — tap only works on rows the viewer could legitimately assign to themselves anyway**
   (their own `Assigned` rows, or `Waiting` ones they're entitled to claim), and every other row stays
   inert with the same on-screen note Android already shows. No new server capability; the admin-wide
   value of «Все» stays purely informational for rows outside that set.

## Out of scope

- Rebuilding `OperatorHub.JoinConversationAsync`'s own assign-then-read order for the *ordinary* queue
  flow — that shape is correct for every other list in the product; this item is only about the one list
  that was never supposed to assign in the first place.
- The console's own admin conversations page, if it already answers this question one way or another —
  worth checking before picking an option, not re-deciding independently of what already ships there.

## Done when

- [ ] The author picks one of the three readings above (or another), and this item is rewritten to that
      scope before any code changes.
