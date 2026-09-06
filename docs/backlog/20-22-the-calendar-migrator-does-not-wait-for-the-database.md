# the calendar migrator does not wait for the database

- **Stage**: 20
- **Status**: done (2026-09-03). **Written retrospectively on 2026-09-06**; see `23-49`.
- **Found**: 2026-09-02/03, split out of `20-21`'s original filing.
- **Note on the number**: `20-22` is also, separately, the number `22-21` gave to an unrelated,
  unstarted planned item ("move a booking, as a chain") before renumbering it to `20-29`. That item's
  file explains the collision from its own side. This file is about the calendar defect that shipped
  **as** `20-22` and is why the number could not move: its commits already say so.

## Written retrospectively

`23-49` counted nine commits naming this item across the workspace. In `ago-calendar` that is one
implementation commit appearing under three hashes with identical trees and the same author timestamp
(`7e2780c`, `c31fcbd`, `82c75b9` — present on more than one ref, not three separate changes); the rest
are `ago-root` documentation sweeps that cite `20-22` in passing while recording other work, plus one
unrelated `fix(15-12)` pair in `ago-calendar-console` whose message happens to contain the digits
`20-22` (matched by the grep, not a real citation of this item — checked by reading the commit, which
is about gate viewport overflow and has nothing to do with the migrator). No backlog file existed for
the item itself until now. Reconstructed from the issue body and the one commit that actually did the
work.

## The gap the issue named

Split out of `#339` ("this was filed as two things joined by 'and' — this is the second," per the
issue's own opening line; `CLAUDE.md` rule 15 was written from the pair). `Ago.Chat`'s migrator waited
for Postgres to accept connections before running; the calendar migrator did not — so its correctness
depended on `ago-deploy`'s init-container wait, and nothing said so. The issue called this application
correctness depending on deployment configuration, "the coupling the platform's own abstractions exist
to remove": it worked only because `ago-deploy` happened to be right, and would break silently the
moment that init container was edited, reordered, or the migrator run any other way — locally, in CI,
or by hand during an incident, which the issue named as exactly when a confusing failure is most
expensive. Filed urgent for the same reason as `20-21`: `20-20` (`#312`) was about to deploy AGO
Calendar to a live node for the first time.

Risk notes in the issue: no `.Result`/`.Wait()`/`.GetAwaiter().GetResult()` in the wait loop, and its
`CancellationToken` must be honoured, since a wait loop is exactly where sync-over-async creeps in; the
wait must be bounded and the bound observable in the logs on the way to failing; and check
`Ago.Platform.*` first, in case this already existed as a package rather than needing implementation.

## What actually shipped

`ago-calendar` commit `7e2780c` — `feat(20-22): the calendar migrator waits for the database itself`:

- Ported `DatabaseAvailabilityWait` and its options unchanged in shape from `Ago.Chat.Migrator`
  (`8-10`): SQLSTATE and socket-error classification separating waitable from permanent failures, a
  bounded poll, and a real `SELECT 1` rather than `pg_isready` or a bare TCP connect.
- The wait wraps only the connectivity probe, never the migration itself — the applier is constructed
  strictly after the wait returns, so a genuine migration failure is still reported immediately instead
  of being retried into a timeout.
- `ago-deploy` is explicitly untouched: its init container stays as belt-and-braces, and what this
  commit removes is the *dependency* on it, not the init container itself.
- **Proof, per the commit message**: run against a real Postgres container whose port is bound but not
  yet listening — the migrator was still running after four seconds of genuinely refused connections,
  then completed once the container started. A wrong password was reported immediately without
  spending any of the wait budget, and an unreachable host failed bounded, naming the wait rather than
  the migration — satisfying the issue's own requirement that the bound be visible in the logs before
  giving up.

## Why the number could not move

Same reasoning as `20-21`'s file: `22-21` found `20-22` also naming an unstarted planned item ("move a
booking, as a chain") and resolved that "the side already written into merged commit messages cannot
move." That planned item became `20-29`; this shipped defect kept `20-22`, because `feat(20-22)`
already says so in `ago-calendar`'s history.

## What is not recoverable

The issue asked whether the wait already existed in `Ago.Platform.*`; the commit message states it was
checked and did not, matching `20-21`'s note, but no separate record of what was searched survives
beyond that sentence.

## Out of scope

- Re-implementing or re-verifying the wait — it shipped and runs in the deployed
  `ago-calendar-migrator`, per `20-20`'s own outcome (which records a `Complete` run in 16s against an
  empty database).
- The hosts' schema guard — `20-21`.

## Done when

- [x] The record exists: what the issue asked for, what actually shipped and how it was proven, and
      why the number stayed here rather than moving with `22-21`'s renumbering.
