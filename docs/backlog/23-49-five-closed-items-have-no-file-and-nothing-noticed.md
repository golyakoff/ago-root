# five closed items have no file in the backlog, and nothing noticed

- **Stage**: 23
- **Status**: done (2026-09-06). Four files written from what survives, and the audit now reads
  closed issues.
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

- [x] Each of the four has a file that says what it was and what shipped, with lost reasoning marked
      as lost rather than filled in.
- [x] `queue-audit.sh` flags a closed item with no backlog file, and is shown doing it.
- [x] How far back the rule applies is decided and written down.

## Out of scope

- Re-doing any of the four. All four shipped; this is about the record, not the work.

## Outcome

**The four are not the same kind of thing, and writing them proved it.**

- **`11-18`** was open for **fourteen minutes** and closed as a duplicate, absorbed into `11-17`. It
  was never implemented under its own number - no commit anywhere names it. Its file says so and is
  deliberately thinner than the others: that is the true shape of what happened, not a gap in the
  reconstruction. `CLAUDE.md` rule 15 was written from this very pair the same afternoon.
- **`11-19`** shipped in one commit and found three real defects on its first run.
- **`20-21`** and **`20-22`** each shipped in one commit - and each **shares its number with an
  unstarted planned item**, already renumbered to `20-28`/`20-29` by `22-21`, because a commit message
  cannot be edited afterwards. Their "nine commits" turned out to be one implementation commit under
  several refs plus later sweeps citing the number, checked rather than repeated from the item's own
  count.

**What could not be recovered is named in each file**, rather than filled in: `11-18`'s implementation
history (there is none), `11-19`'s exemption-list iterations, and for both calendar items *what was
actually searched* when their issues asked to check `Ago.Platform.*` first - the commits confirm it was
done and found nothing, and nothing records what was looked at.

**The check reuses the existing file-existence test rather than inventing a stricter one.** Matching
file content to issue content would have mis-flagged `11-17`, which legitimately carries two closed
issues on one file by `22-21`'s own prior resolution. A second, stricter definition of *has a record*
that disagreed with the first would have been a new source of false findings.

**How far back was decided on evidence, not assumption.** `ago-root`'s entire issue history begins at
`#312` on 2026-09-02, so there is no pre-convention era to exclude; the script says `--limit 500` means
*all of them, with headroom*, and names size rather than age as the trigger to revisit - and requires a
reason per entry if a cutoff is ever added, the way `secrets-audit.sh`'s allow-list already does.

Verified at landing rather than taken from the report: moving `11-19`'s new file aside makes the audit
name it, and restoring it makes the audit clean again.