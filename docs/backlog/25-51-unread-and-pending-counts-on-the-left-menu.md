# 25-51 · Unread and pending counts on the left menu

- **Stage**: 25
- **Status**: ready — **not yet verified against the real code** (docs/backlog/README.md)
- **Depends on**: `25-50` (the final menu shape/labels this item's badges attach to)
- **Found**: 2026-09-12, `feedback.md` — the most complex single item in this batch; read the whole
  spec before starting, the rules differ between the two menu sections it touches

## What is actually true

The left menu shows no indication of new messages or pending bookings today. The author wants a
numeric badge system, with two genuinely different semantics for the two sections it applies to.

## Scope

**Диалоги (conversations) — "unread" semantics:**
- A badge on "Мои" showing the count of unread messages across the operator's own assigned
  conversations. If "Диалоги" is collapsed (its own "Мои" sub-item not visible), the badge moves to
  "Диалоги" itself, carrying the same sum.
- Two conversations with unread counts of 2 and 3 show a combined badge of 5 on whichever menu level
  is currently visible.
- Opening a conversation and viewing its messages marks them read: if that conversation was the only
  source of the operator's unread count, the badge disappears entirely; otherwise it decreases by
  exactly the number of messages just read.

**Записи (calendar bookings, `25-50`'s own rename) — "pending" semantics, deliberately different:**
- A badge on whichever Записи sub-item shows what needs action (пункт "В ожидании" — check `25-50`'s
  final label), counting bookings still awaiting confirmation.
- **Unlike Диалоги, merely viewing a pending booking does not clear it.** The count only decreases
  when a booking is actually confirmed or otherwise leaves the pending state — being seen is not the
  same as being resolved, and the badge must reflect "still needs your decision," not "still unread."

**Mobile, both sections, when the menu itself is collapsed (hamburger visible, menu items not):**
- A single small badge overlays the menu-open button itself, showing the sum of both sections'
  counts (Диалоги's unread + Записи's pending) — the same "app-icon notification badge" shape as a
  phone's home screen.
- When the menu is expanded on mobile, badges return to their own per-item place exactly as on
  desktop (desktop menu is always expanded, so this collapsed-sum state is mobile-only).

## Where this is likely to go wrong

- **Do not use one mechanism for both sections.** Диалоги's count is read-state on messages;
  Записи's count is a real business-state condition (pending vs. confirmed). Sharing one "notification
  count" abstraction between them would either wrongly clear a pending booking on view, or wrongly
  leave a read conversation's badge stuck.
- **Real-time**: this should update live as new messages arrive or new bookings enter/leave pending,
  the same real-time discipline the rest of the operator console already has (SignalR) — not a
  poll-every-N-seconds count that lags behind what `25-51`'s own sibling panels already show live.
- **The mobile collapsed-sum badge is derived, not a third independently-tracked count** — it is
  always Диалоги's own count plus Записи's own count, computed from the same two numbers the expanded
  menu shows, never a separate query.

## Done when

- [ ] Диалоги shows an unread-message count, summed and positioned correctly whether "Мои" is
      visible or the section is collapsed; reading a conversation's messages clears or decreases it.
- [ ] Записи shows a pending-bookings count; viewing a pending booking does **not** clear it — only
      confirming it (or its own equivalent resolution) does.
- [ ] Both counts update live, without a page reload, as the underlying facts change.
- [ ] On mobile with the menu collapsed, one small badge on the menu-open button shows the sum of
      both sections' counts; expanding the menu shows them split back onto their own items.
