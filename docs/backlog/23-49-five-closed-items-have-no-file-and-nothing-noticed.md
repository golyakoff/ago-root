# five closed items have no file in the backlog, and nothing noticed

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing
- **Decision**: none needed for the gap. One small choice inside it is named at the bottom.

## What is actually true, counted on 2026-09-06

Of the 94 items closed since 2026-09-01, **four have no file in `docs/backlog/` at all**:

| Item | Issue | Closed | Traces left behind |
|---|---|---|---|
| `11-18` — one console screen prints an unlabelled local time | `#344` | 2026-09-03 | **none** — no file, no commit in `ago-root`, no mention in any other item |
| `11-19` — the calendar console's gate checks that everything is translated | `#350` | 2026-09-03 | one commit |
| `20-21` — the calendar hosts have no schema guard | `#339` | 2026-09-03 | nine commits, two items cite it |
| `20-22` — the calendar migrator does not wait for the database | `#340` | 2026-09-03 | nine commits, two items cite it |

**`25-02` was the fifth**, found separately the same day and written retrospectively — its deliverable,
`docs/compliance-checklist.md`, had shipped *twice* while its item file never existed.

## Why this is worse than untidy

`CLAUDE.md` rule 14 makes the backlog file the record: *the file in `docs/backlog/` and one issue in
`ago-root`*. When only the issue exists, the reasoning is gone the moment the issue scrolls away —
what the item was for, what was considered and rejected, what it deliberately did not do.

`20-21` and `20-22` are the sharpest case: **two other items cite them by number** as though a reader
could go and look. There is nothing to look at. And `11-18` left no trace anywhere at all — a title in
a closed issue and nothing else.

## Why nothing caught it

`tools/queue-audit.sh` reads **open** issues and matches them to files. A closed issue is not read, so
an item that never had a file is invisible to it by construction — and stays invisible forever,
because closing is the only thing that would have made anyone look.

This is the same shape as `23-28` (a part-finished item with unticked boxes is invisible in the other
direction) and `23-44` (an invariant asserted in a comment that nothing checked). Three in one day is
a pattern rather than three coincidences: **every one of them is a rule the project genuinely keeps,
with nothing mechanical keeping it.**

## Scope

- Write the four missing files from what the commits and issues actually record — **as records of
  what shipped, not as reconstructions of what somebody might have intended.** Where the reasoning is
  lost, say it is lost. A confident invention is worse than an admitted gap.
- Extend `queue-audit.sh` to read **closed** issues too, and flag any whose item has no file. It
  already enumerates repositories rather than keeping a list; this is the same walk with the state
  filter widened.

## The small choice inside it

**How far back to sweep.** Ninety-four items since 1 September were checked here. There are older
closed items and this sweep did not look at them: doing so may turn up more, or may turn up items from
before the convention settled, where a missing file is not a defect. Cheap to find out, and worth
deciding rather than drifting into.

## Done when

- [ ] Each of the four has a file that says what it was and what shipped, with lost reasoning marked
      as lost rather than filled in.
- [ ] `queue-audit.sh` flags a closed item with no backlog file, and is shown doing it.
- [ ] How far back the rule applies is decided and written down.

## Out of scope

- Re-doing any of the four. All four shipped; this is about the record, not the work.
