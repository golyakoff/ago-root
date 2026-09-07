# the role-assignment backfill was never counted

- **Stage**: 22
- **Status**: ready
- **Depends on**: `22-16` (the backfill), `22-26` and `22-27` (the three reasons it could not run).
  All shipped.
- **Carried out of**: `22-16`, whose first Done-when this is. Filed under CLAUDE.md rule 14.
- **Decision**: none. This is a measurement, not a choice.

## What `22-16` asked for, and what the record shows

`22-16`'s first Done-when is deliberately worded against the failure it expects:

> Every pre-existing tenant whose account-side roles carry calendar permissions has them in
> `role_assignment_projections` — **verified by count against `ago_chat`, not by running the tool and
> assuming.**

The tool is built and its behaviour is proven — republish through the real outbox, idempotent by
construction, five integration tests including a real before-and-after double run. **The count is not
anywhere.** Nothing in `ago-root`, `ago-chat` or `ago-deploy` records a number taken after a
successful run.

What the record *does* show is the reason to distrust the assumption. Running the backfill on
2026-09-04 found three separate reasons it could not run at all, none of which any test or CI job
could have caught:

| | |
|---|---|
| `22-26` | absent from `ago-chat`'s Dockerfile — the image could not be built (`MSB1009`, naming neither the project nor the omission) |
| `22-27` | absent from `build-images.sh` — nothing ever tried to build it |
| `22-27` | absent from the `postgres-ingress` NetworkPolicy — the pod could not reach the database, the identical failure `8-08`'s migrator hit |

Those were fixed and `ago-deploy/k8s/run-backfill.sh` was written to make the run repeatable. **The
trail stops there.** So the state of `role_assignment_projections` today is unknown: possibly correct,
possibly still two rows against thirty sites.

## Why this is worth a number rather than a line in a runbook

The failure is silent by design. `19-03`'s console renders calendar screens as **absent, not broken**
for a person without the permission, so "your tenant predates the projection" and "you were never
granted the calendar" look identical on screen — which is how `22-16` came to exist at all, and why
its author insisted on a count rather than a run.

It also blocks the only thing that would notice: `20-30` (the calendar's first real sign-in) and
`22-06`'s own unmet Done-when both need a person to reach a calendar screen, and a missing projection
row is exactly what would stop them while looking like an ordinary absence of permission.

## Scope

- Run `ago-deploy/k8s/run-backfill.sh` on the node, or establish that it already ran.
- **Take the count, both sides.** Roles in `ago_chat` carrying a calendar permission, against rows in
  `role_assignment_projections`. `22-16` recorded 2 against 30 sites on the day it was found; the
  comparable numbers today are the deliverable.
- **Record them where a later reader will find them**, with the date. A number in a session
  transcript is what this item exists because of.
- If the two do not agree, that is a finding: say which tenants are missing and why, and file it.

## Out of scope

- Changing the backfill. It is proven, idempotent, and running it twice is safe by construction.
- Making the run part of every deploy. `22-27` decided against that deliberately — a one-shot
  corrective is not a step of deploying — and nothing here reopens it.
- Granting anybody the calendar. That is `22-07` (bought) and `22-17` (granted); this item only moves
  grants that already exist on the account side into the projection that reads them.

## Done when

- [ ] The backfill has run to completion on the node, and the run's own output is quoted rather than
      summarised.
- [ ] Roles in `ago_chat` carrying a calendar permission and rows in `role_assignment_projections` are
      counted on the same day and the two numbers are stated together.
- [ ] Both numbers, and the date, are written where somebody looking at `22-16` will find them.
