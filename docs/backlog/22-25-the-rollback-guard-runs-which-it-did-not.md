# the rollback guard runs, which it did not

- **Stage**: 22
- **Status**: done (2026-09-04), `ago-deploy` — written retrospectively 2026-09-07.
- **Found**: 2026-09-07 by `queue-audit.sh`'s new orphan-scope check (`22-29`), which was built to
  find `22-26` and `22-27` and found this one as well.

## What this was

`fix(22-25): the rollback guard runs, which it did not` — `22-24`'s guard in `apply-demo.sh`, which
refuses an apply that would move a running workload back to a tag nothing is running, was not
actually executing. The commit made it run.

**Why it was not running is not recorded anywhere**, and this file does not invent a reason. The
commit message names the symptom and the fix; the cause is lost.

## Why it has a file at all

It had none, and no issue in any repository — it existed only as a commit subject. That makes the
number read as free to the next person who needs one in this stage, which is `22-29`'s whole subject
and the reason the check that found this exists.

## What is worth knowing beside it

The same guard turned out to have a second defect found separately: its manifest-side pattern excluded
digits, so `ago-demo-shop1` and `ago-demo-shop2` were never covered by it (`15-22`, fixed 2026-09-07).
A guard that did not run, and then ran while silently covering five deployments out of seven, is worth
seeing as one story rather than two coincidences.

## Done when

- [x] The guard executes. Delivered 2026-09-04; the commit is the record.
- [~] Why it was not executing is understood. **Not recovered** — the commit says what was fixed and
      not what was wrong, and no issue or discussion survives. Recorded as lost rather than guessed at.
