# seeding a permission publishes nothing, so the calendar never learns

- **Stage**: 23
- **Status**: done
- **Depends on**: `23-102`, which introduced the write no publisher covers.
- **Found**: 2026-09-08, on the first tenant sign-in after the first successful grant.

## What happened

`23-102` shipped, `ago-deploy` declared the permissions, the platform owner re-granted the calendar,
and **chat's roles are correct**:

- Admin: `calendar:configure` (plus its six existing)
- Operator: `booking:confirm`, `booking:reject`, `booking:cancel`, `booking:mark_no_show`,
  `customer:read`, `customer:edit` (plus its five existing)

The tenant signed in, the calendar nav unlocked — and the Workers screen answered:

> У вашей учётной записи оператора нет права на это действие в этом арендаторе.

**Because the calendar checks its own copy.** `ago_calendar.role_assignment_projections` for that
operator still held only the chat permissions, with `updated_at` **four days old** — it never learned.

## Why, exactly

`RoleAssignmentsChanged` is enqueued in four places: removing an operator, redeeming an invite,
registering a site, and `RoleAssignmentProjectionBackfill`. **None of them fires when a role's
permissions change**, and until `23-102` nothing changed a role's permissions after registration — so
the gap did not exist to be missed.

`23-102` created that write and published nothing. It fixed one side of a fact that lives in two
databases.

## Why this is the sharpest possible example of `adr/0093`'s cost

That ADR's own Consequences already say it: two schemas, two databases, and anything crossing them
crosses at-least-once delivery and must be *provable*. `22-32` exists because of it.

This is that cost arriving in the smallest possible form — **one array column, copied, and the copy is
what the enforcement reads.** Chat's roles being right is not the same as the tenant being able to act,
and no amount of correctness on chat's side substitutes.

## Scope

- **Seeding permissions publishes**, so the projection learns — through the same outbox the other four
  publishers use, never a direct write into the other product's database.
- **Every operator holding the affected role**, not only one: the projection is keyed by subject, and a
  role's permissions change affects everybody who holds it.
- **Idempotent**, since the consumer is (rule 5) and a re-grant is expected — the author performed one
  the same day.

## Where this is likely to go wrong

- **Do not fix it by having the calendar read chat's tables.** `adr/0093` forbids it and the projection
  exists precisely so it cannot happen.
- **The backfill is a repair, not the fix.** `RoleAssignmentProjectionBackfill` republishes for every
  operator and unblocks a stuck tenant today, but a tool somebody has to remember to run is what this
  item exists to stop needing.
- **Check the other direction too.** If seeding permissions was missing a publisher, ask what else
  writes `roles.permissions` — `23-72`'s role changes, and anything a future item adds.

## Done when

- [x] Seeding now enqueues `RoleAssignmentsChanged` in the same transaction as the permissions
      write (rule 4), so the projection learns without `run-backfill.sh`. Proven by test with a
      fails-before; **the first grant on the stand since this deployed is the field proof, and it has
      not happened yet** - the code went live 2026-09-08, shortly before this was written.
- [x] One event per currently-linked operator holding the affected role, each carrying that
      operator's full permission union across every role they hold - the account owner holds two and
      would otherwise have received half their own permissions. Candidates are re-checked under
      `SELECT ... FOR UPDATE` so a removal committing in the gap is caught rather than inherited
      from a stale list.
- [x] Checked against the stand on 2026-09-08: that tenant's row in
      `ago_calendar.role_assignment_projections` carries `booking:confirm`, `booking:reject`,
      `booking:cancel`, `booking:mark_no_show`, `customer:read`, `customer:edit` and
      `calendar:configure`, and the author confirmed the calendar sections opened.
