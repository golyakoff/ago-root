# the calendar hosts have no schema guard

- **Stage**: 20
- **Status**: done (2026-09-03). **Written retrospectively on 2026-09-06**; see `23-49`.
- **Found**: 2026-09-02/03, by `20-20`'s own deploy — its comments named this as owed rather than done.
- **Note on the number**: `20-21` is also, separately, the number `22-21` gave to an unrelated,
  unstarted planned item ("an operator creates a customer and a booking") before renumbering it to
  `20-28`. That item's file explains the collision from its own side. This file is about the calendar
  defect that shipped **as** `20-21` and is why the number could not move: its commits already say so.

## Written retrospectively

`23-49` counted nine commits naming this item across the workspace. In `ago-calendar` that is one
implementation commit appearing under three hashes with identical trees and the same author timestamp
(`fae2c2a`, `b07e908`, `f780501` — present on more than one ref, not three separate changes); the rest
are `ago-root` documentation sweeps that cite `20-21` in passing while recording other work. No backlog
file existed for the item itself until now. Reconstructed from the issue body and the one commit that
actually did the work.

## The gap the issue named

`Rewritten 2026-09-03 to one thing`, per the issue's own header: it had been filed as *"no schema
guard **and** the migrator no database wait"* — two mechanisms, two layers, two proofs, sharing only
the repository and the accident of being noticed at once. `CLAUDE.md` rule 15 ("one ticket, one thing")
was written from exactly this split; the migrator's half became its own item, `20-22`.

`Ago.Chat.*` hosts already refused to start against a database whose schema they did not expect
(`8-08`/`adr/0056`); `Ago.Calendar.Api` and `Ago.Calendar.Worker` did not. The issue named the failure
mode this guards against as quiet by nature: a host rolled forward against a stale schema does not
crash — it runs, and fails later on whichever column it happens to touch first, at request time, for
whoever sent that request. On a rolling deploy that is a window where some pods lie about being
healthy. It was filed as urgent because `20-20`(`#312`) was about to deploy AGO Calendar to a live node
for the first time, making the gap real rather than theoretical.

The issue's own risk notes: check `Ago.Platform.*` first, in case the guard already existed as a
package rather than needing a second implementation; and the dependency rule is not negotiable — a
schema check touches a database, so the port belongs in `Application/Abstractions` and the adapter in
`Infrastructure.*`, wiring only in the hosts.

## What actually shipped

`ago-calendar` commit `fae2c2a` — `feat(20-21): a schema guard for Ago.Calendar.Api and
Ago.Calendar.Worker`:

- Confirmed neither the guard nor the migrator's wait existed in `Ago.Platform.*` — both are
  `Ago.Chat`-specific code with nothing to consume, so this ports rather than references, matching
  what the issue asked to be checked first.
- Added `SchemaVersionGuard`, `SchemaGuardOptions`, `SchemaOutOfDateException` and
  `SchemaGuardHostExtensions` under `Schema/`, wired from both `Ago.Calendar.Api/Program.cs` and
  `Ago.Calendar.Worker/Program.cs`.
- **Proof, per the commit message**: spawned the real published `Ago.Calendar.Api.dll` against a
  schema deliberately one migration behind — non-zero exit, the exception named, the missing migration
  named, and (the assertion that actually matters) nothing ever answered on its port, so a refusal that
  still served would have been caught. A positive control ran the identical binary on the identical
  port with only the schema differing, and an IL-scanning arch test fails for any host that forgets to
  call the guard — closing the class of failure the issue's own risk section warned about: a guard
  wired wrong looking identical to one wired right until it matters.

## Why the number could not move

`22-21` found eight item numbers each naming two different things, `20-21` among them. Its resolution:
*"the side already written into merged commit messages cannot move" — a commit message is the one
record here that is never edited.* The unstarted planned item that had also been filed under `20-21`
moved to `20-28`; this shipped defect kept the number, because `feat(20-21)` already says so in
`ago-calendar`'s history.

## What is not recoverable

The issue's own "where this will go wrong" section asked whether the guard already existed in
`Ago.Platform.*` — the commit message confirms it was checked and did not, but no separate record of
that check (what was searched, what was ruled out) survives beyond that one sentence.

## Out of scope

- Re-implementing or re-verifying the guard — it shipped and runs in the deployed `ago-calendar-api`
  and `ago-calendar-worker`, per `20-20`'s own outcome.
- The migrator's database wait — `20-22`.

## Done when

- [x] The record exists: what the issue asked for, what actually shipped and how it was proven, and
      why the number stayed here rather than moving with `22-21`'s renumbering.
