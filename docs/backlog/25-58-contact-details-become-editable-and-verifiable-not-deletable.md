# 25-58 · Contact details become editable and verifiable, not silently deletable

- **Stage**: 25
- **Status**: ready — fully specified via the author's own answers, 2026-09-12
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md`, sharpened through direct investigation and the author's own
  answers (recorded below)

## What is actually true, confirmed by reading the real code

`ContactDetailsPanel.tsx`'s "Удалить" button (`DeleteVisitorContactDetailHandler`) permanently
deletes a `VisitorContactDetail` row with no distinction between one the visitor typed themselves and
one an operator typed manually — same button, same permission (`conversation:send`), for both. The
separate form below it (`RecordVisitorContactDetailHandler`) only ever **creates a new row**
alongside whatever the visitor already submitted; it never edits or overrides an existing entry —
confirmed by reading both handlers, not assumed.

## The author's own decisions, 2026-09-12

- **Real inline editing**, not a second parallel entry. An operator who hears a corrected phone
  number or a spelling fix from the visitor mid-conversation should be able to fix the existing
  entry directly, not create a second, competing one from a different source.
- **Phone and Email gain a confirm / mark-invalid action** — an operator-asserted state distinct
  from `ChannelIdentitiesPanel`'s own verified-channel mechanism (`25-46`'s tooltip work explains that
  distinction where it's shown; this item does not conflate the two). "Confirmed" and "invalid" are
  both states an operator can set on an existing Phone or Email entry.
- **Name is taken on trust** (no confirm/invalid state — a name has no verifiable channel the way a
  phone or email does), but an operator can still edit it to fix a visitor's own typo.
- **The "Удалить" button is removed.** The author's own instruction: remove it unless a real, useful
  case exists. Investigated and none was found that this item's own edit/confirm/invalid mechanism
  doesn't already cover — a wrong value gets corrected (edit) or flagged (mark invalid), which is
  strictly more informative than deleting it outright. A genuine data-subject erasure request is a
  different mechanism entirely (`16-02`/`16-03`'s own scope, gated and audited very differently from a
  casual button in this panel) and stays out of this item.

## Scope

- `ContactDetailsPanel.tsx`: each Phone/Email/Name entry gets an inline edit (pencil) action.
- Phone and Email entries additionally get confirm/mark-invalid actions, each its own persisted state
  on the `VisitorContactDetail` row.
- Remove the separate "add a new record" form and the "Удалить" action entirely.
- Fix the Phone/Email/Other pill labels while this file is open — Russian labels ("Телефон",
  "Электронная почта", the third source's own real label — check what `Other` actually represents
  before choosing its Russian name), and drop the repeated "непроверенные" prefix on every line per
  the feedback's own complaint about visual noise; the panel's own header already states the section
  is about unverified data once, which is enough.

## Where this is likely to go wrong

- **Don't conflate "confirmed by an operator" with `ChannelIdentitiesPanel`'s own "verified channel
  identity."** They are different mechanisms answering different questions — this item's confirm/
  invalid state is an operator's own assertion, never proof of address ownership the way a channel
  link is.
- **Editing changes the existing row, not the source.** If a visitor's own self-submitted entry gets
  edited by an operator, the row's own `Source` stays what it was (`Visitor`) — this is a correction,
  not a reassignment of who originally provided it. Confirm this distinction is preserved before
  landing; getting it backwards would misattribute a visitor's own data to an operator.

## Done when

- [ ] Phone, Email and Name entries are each editable in place (pencil action), never via a second
      parallel form.
- [ ] Phone and Email entries can be marked confirmed or invalid by an operator, persisted.
- [ ] The "Удалить" action and the separate "add new record" form are both gone.
- [ ] Pill labels read real Russian words, not "Phone"/"Email"/"Other", and the "непроверенные"
      prefix is not repeated per line.
