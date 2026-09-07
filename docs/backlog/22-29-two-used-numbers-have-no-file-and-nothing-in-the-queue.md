# two used numbers have no file, and nothing in the queue knows they exist

- **Stage**: 22
- **Status**: done (2026-09-07). Both files written; `tools/queue-audit.sh` extended and shown
  catching a live, unrelated third case (`22-25`) while it was being tested. See Outcome.
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

- [x] `22-26` and `22-27` each have a file saying what shipped, with lost reasoning marked as lost —
      `docs/backlog/22-26-the-backfill-host-could-not-be-built-into-an-image.md` and
      `docs/backlog/22-27-the-backfill-had-no-way-to-be-built-admitted-or-run.md`, each built only from
      its one commit (`ago-chat@44355d3`, `ago-deploy@bc55af0` respectively) — there was never an issue
      to read for either.
- [~] Both numbers are visibly taken rather than reading as free — **taken by file**, which is what
      actually stops the number reading as free: `tools/queue-audit.sh`'s new check (below) already
      stops flagging both once their files exist. The second layer of visibility rule 14 asks for — one
      issue per item in `ago-root` — is not done by this session: opening an issue is the author's own
      action under this item's standing instructions, and the two titles/bodies are handed back in the
      report for that.
- [x] The "can anything notice this automatically" question is answered either way, in writing — see
      Outcome. Built, not merely proposed: `tools/queue-audit.sh` gained a new pass, and while it was
      being tested against this project's real history it flagged a third, genuinely unaddressed case
      (`22-25`) that this item never knew about — named in the Outcome section, filed by nobody yet,
      deliberately not fixed here since it is outside this item's two numbers.

## Outcome

**What each one actually was, from its one commit — there was never an issue for either.**

`22-26` (`ago-chat@44355d3`): `Ago.Chat.RoleAssignmentBackfill` was absent from `ago-chat`'s
Dockerfile's enumerated restore layer, so the image could not be built at all — `MSB1009: Project file
does not exist`, a message naming neither the project nor the omission. One `COPY` line, proven on the
node before landing.

`22-27` (`ago-deploy@bc55af0`): with `22-26` fixed, the image still could not be built by anything
(`build-images.sh` named only the four serving hosts), could not reach the database (absent from the
`postgres-ingress` NetworkPolicy — the identical failure `8-08`'s migrator had already hit, on a page
that already said what to do about it), and could not be run more than once by hand. Three files
changed: the build list, the NetworkPolicy, and a new `run-backfill.sh`, deliberately kept outside the
deploy overlay because the backfill is a one-shot corrective, not a step of every deploy.

**What could not be recovered, named rather than guessed at**: for both, why the omission happened in
the first place — whether it was noticed and deferred or never checked at all. Each commit message
records what was found and fixed, not what was looked at beforehand. Both files say this plainly rather
than filling the gap with a plausible-sounding reason.

**The mechanical-check question, answered by building it.** `queue-audit.sh` gained a new pass, placed
after the existing closed-issue checks, that reads commit *subject lines only* (never bodies, where
`NN-NN` is constant prose — "the identical failure `8-08`'s migrator hit", "cited by `20-21`") on
`origin/main` across every repository the script already reads, for the project's own convention of a
leading `type(NN-NN[, NN-NN...]):` scope, and flags any item named there with no `docs/backlog/` file
at all.

Two decisions made it that narrow rather than noisy:

- **Subject only, never body.** The scope position is written by one project-wide convention; the body
  is free prose. Matching the body was never tried — the risk this item itself named (crying wolf on
  every `NN-NN` reference in prose) is obviously real there and obviously not in the scope position.
- **A backlog *file* as ground truth, not a GitHub issue.** Matching against issues was tried first and
  rejected on evidence: the per-item-issue convention began at `ago-root#312` on 2026-09-02, so every
  item from the stages before that has commits naming it and no issue at all — checking issues flagged
  well over a hundred of them, which is exactly the cried-wolf failure this item warned against. A
  backlog file is the one record that has existed since the start of the project.

**Run against this project's actual history** — roughly 1,200 commit subjects across nine repositories
on `origin/main` — it produced exactly three hits and zero false positives: `22-26` and `22-27`
(quieted the moment their files were added in this same change) and one more, unrelated and still open:
`22-25` in `ago-deploy` (`fix(22-25): the rollback guard runs, which it did not`), which has no backlog
file and, as far as this session could find, no issue and no other document either. It is the same
shape as this item's own two numbers, found by the check this item built, on the day this item happens
to be handled — and it is **not fixed here**: it belongs to neither `22-26` nor `22-27`, and this
item's scope is those two numbers, not everything the new check might ever find. It is named in the
handback for the author to file under a number of its own.

No addition needed beyond the check itself and the one section of report it changes: it slots into the
existing `full` mode, needs no new `gh` call (it reads only the local clones the script already has, so
it keeps working when GitHub does not answer), and its own flagged count folds into the script's
existing summary line without a separate one.

## Out of scope

- Re-doing either `22-26` or `22-27`. Both shipped on 2026-09-04; this is about the record.
- `15-20`, whose file existed and merely said `ready` after it shipped — fixed in the same change that
  found this, not carried here.
- `22-25`, found by the new check while this item was being verified. Same shape as this item, not
  this item's number, not fixed here — handed back to the author to file.
