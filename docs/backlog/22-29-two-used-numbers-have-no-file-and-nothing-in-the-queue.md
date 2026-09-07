# two used numbers have no file, and nothing in the queue knows they exist

- **Stage**: 22
- **Status**: ready
- **Depends on**: nothing. Same shape as `23-49`, which fixed four of these and taught the audit to
  read closed issues.
- **Found**: 2026-09-07, while settling `23-55`.

## What is actually true

`22-26` and `22-27` exist **only as commit messages**. No file in `docs/backlog/`, no issue in
`ago-root`. Both were real: they are the three reasons the `22-16` role-assignment backfill could not
run on 2026-09-04 — the tool absent from the Dockerfile, absent from `build-images.sh`, and blocked by
the `postgres-ingress` NetworkPolicy.

That work shipped. Its reasoning did not.

## Why this is worse than untidy, and it is not the same failure as `23-49`

`23-49` found closed items whose *issues* existed and whose files did not. These have neither. So they
are invisible to every check by construction — `queue-audit.sh` walks issues, and there are none to
walk.

**The sharper cost is that the numbers read as free.** `22-21` describes exactly this: a used number
with nothing behind it looks available, and the next person to need a stage-22 number may take one of
these. Then two different pieces of work share an identifier, and the older one — the one with no file
— is the one that loses.

`22-28` was filed the same day and deliberately skipped over both of these rather than reusing them,
which is how they were noticed.

## Scope

- Write both files from what the commits actually record, marking lost reasoning as lost rather than
  filling it in. A confident invention is worse than an admitted gap (`23-49`'s own rule).
- Open the two issues, closed as completed, so the numbers are visibly taken.
- Ask whether anything mechanical could notice a number used in a commit message with no file behind
  it. `queue-audit.sh` already walks every repository's log for other reasons; this may be a cheap
  addition or may be a grep that cries wolf on every `NN-NN` reference in prose. Decide, do not drift.

## Done when

- [ ] `22-26` and `22-27` each have a file saying what shipped, with lost reasoning marked as lost.
- [ ] Both numbers are visibly taken rather than reading as free.
- [ ] The "can anything notice this automatically" question is answered either way, in writing.

## Out of scope

- Re-doing either. Both shipped on 2026-09-04; this is about the record.
- `15-20`, whose file existed and merely said `ready` after it shipped — fixed in the same change that
  found this, not carried here.
