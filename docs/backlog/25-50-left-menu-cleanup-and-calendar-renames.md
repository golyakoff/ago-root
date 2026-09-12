# 25-50 · Left menu cleanup and calendar section renames

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md`

## What is actually true

`ago-console`'s left menu (`consoleNav.ts`) today: shows a "Разделы консоли" heading; child-item
font size is smaller than top-level items; the Calendar section is labelled "Календарь" and its
confirmed-bookings sub-item is labelled "Записи" (`navCalendarQueue`="В ожидании",
`navCalendarBookings`="Записи").

## Scope

- Remove the "Разделы консоли" heading text entirely — it is not shown anywhere else in either
  mobile or desktop layout.
- Increase child (sub-item) menu font size to match top-level items.
- Rename: the Calendar section's own top-level label "Календарь" → "Записи"; its own confirmed-
  bookings sub-item "Записи" → "Утверждённые". (This is a two-way relabel, confirmed against the
  author's own literal wording — not a typo to "fix" back.)
- Reorder top-level menu items: **Диалоги**, **Записи** (the renamed Calendar section), then every
  remaining item in its current relative order.

## Where this is likely to go wrong

- **This item does not touch `25-51`'s own unread-count badges** — that is real state/behavior and
  its own item, even though it lands on the same menu structure this item reorders and relabels.
  Land this one first; `25-51` reads whatever final menu shape this item leaves.

## Done when

- [ ] "Разделы консоли" text is gone from the left menu in every layout.
- [ ] Child menu items render at the same font size as top-level items.
- [ ] Calendar section reads "Записи" (was "Календарь"); its confirmed-bookings sub-item reads
      "Утверждённые" (was "Записи") — routes/behavior unchanged, labels only.
- [ ] Menu order is Диалоги, Записи, then the rest unchanged.
