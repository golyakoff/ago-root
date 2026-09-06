# twelve closed items still carry an unsettled Done-when

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. Carried out of `23-50`, whose fourth Done-when this is.
- **Decision**: none needed. The rule is already decided; this is the backlog it created.

## Where this comes from

`23-50` made the boxes the record: **a ticket does not close while a Done-when box is unsettled**, and
settled means ticked, `[~]` with a sentence, or carried out to its own number. `queue-audit.sh` now
flags a closed item that breaks it.

On the day the rule landed it flagged **eighteen** closed items. Six were settled the same evening,
and settling them turned out to be almost mechanical: **their `Status` lines already said the box was
unmet and why** — *"stay open on purpose"*, *"honestly unmet"*, *"met by description rather than by a
built check"*. The truth was written; it was simply in the wrong place for a check to find. Moving it
onto the box changed no facts.

**These twelve are different, and that is the whole reason they are a separate number.**

## What is left, and why it needs judgement rather than a sweep

| | |
|---|---|
| `24-02` | 4 |
| `23-18` | 5 |
| `22-20` | 3 |
| `15-18` | 2 |
| `15-17` | 4 |
| `17-12` | 2 |
| `22-16` | 3 |
| `13-08` | 5 |
| `15-13` | 2 |
| `20-27` | 2 |
| `11-16` | 4 |
| `11-14` | 3 |

Every one says plainly `Status: done`, with a pull request against it and **no qualifier**. So unlike
the six, nothing in the file tells you whether a box is true. Each has to be read against what the
item actually shipped.

**The wrong way to finish this is to tick them.** Thirty-nine boxes, ticked in one pass on the say-so
of a `Status` line, would produce exactly the reassurance `23-50` exists to remove — and the three
real defects that motivated the whole rule (`22-09`, `22-18`, `17-11`) all had a confident `Status`
line too.

## Scope

- For each of the twelve, read the item's own Outcome and the change it names, and settle every box
  one of the three legal ways.
- **Where a box cannot be confirmed from the record, say so on the box** rather than ticking it. An
  admitted gap is worth more than a tick nobody can defend.
- `11-14` is worth reading first: its `Status` says *half done* and names `ago-calendar-console`,
  which `22-06` folded into the one console — so at least one of its boxes may be overtaken rather
  than unmet, the same shape `20-20`'s retired hostname turned out to be.

## Done when

- [ ] All twelve carry only settled boxes, and `queue-audit.sh` reports no `UNSETTLED`.
- [ ] Every box settled as `[~]` says *what shipped instead*, not merely that it did not.
- [ ] Any box that turns out to be genuinely undone gets its own number rather than a tick.

## Out of scope

- Re-doing any of the twelve. All twelve shipped; this is about their record.
- The rule itself, which `23-50` settled.
