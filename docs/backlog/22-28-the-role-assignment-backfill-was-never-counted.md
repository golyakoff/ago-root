# the role-assignment backfill was never counted

- **Stage**: 22
- **Status**: done — counted on the live node, 2026-09-14, by the managing session directly (not a
  code change; see the Outcome section).
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

- [x] The backfill has run to completion on the node, and the run's own output is quoted rather than
      summarised. — see Outcome.
- [x] Roles in `ago_chat` carrying a calendar permission and rows in `role_assignment_projections` are
      counted on the same day and the two numbers are stated together. — see Outcome.
- [x] Both numbers, and the date, are written where somebody looking at `22-16` will find them. — this
      section.

## Outcome

Counted directly on the live node, 2026-09-14, by the managing session (`kubectl exec` into the
`postgres` pod, real SQL, no code change — this item is a measurement, not a build).

**The backfill had already run**, 5 days 20 hours before this count (`ago-chat-roleassignment-backfill`
Job, `Completed`, 0 restarts). Its own quoted output:

```
Cannot load library libgssapi_krb5.so.2
Error: libgssapi_krb5.so.2: cannot open shared object file: No such file or directory
11 candidate operator(s) considered (currently active, external identity linked).
11 RoleAssignmentsChanged event(s) staged to the outbox.
  site 00000000-0000-0000-0000-000000000001: 3 operator(s) republished
  site 00000000-0000-0000-0000-000000000008: 2 operator(s) republished
  site 01a0437a-5f2e-7fab-936f-b70a95f681f9: 1 operator(s) republished
  site 01a06262-d4f0-7fb6-94e0-9ff702db8a43: 1 operator(s) republished
  site 01a07c5b-12ab-7ce3-9359-a263b27ee3cc: 1 operator(s) republished
  site 01a07c71-dad7-7eed-80b7-9e91b8d6d38a: 1 operator(s) republished
  site 01a07f9c-087b-7485-ba0e-91db99613d94: 1 operator(s) republished
  site 01a08013-179e-7357-960e-8efdcb2ca9a6: 1 operator(s) republished
Nothing here talks to the broker - Ago.Chat.Worker's own OutboxDispatcher publishes these on its next
poll, exactly like every other publisher of this event.
```

The `libgssapi_krb5` lines are a non-fatal warning (an unused optional Kerberos library path Npgsql
probes for) — the run itself completed and staged all 11 events; not investigated further here, out of
this item's own scope.

**The two counts, today**: `ago_chat` currently holds **7 operators total** (all active, all with a
linked external identity, down from the 11 the backfill saw 5 days 20 hours ago — the population
shrank via `DemoTenantExpiryJob`, not via any removal this item touched). Of those 7, **1** holds a role
carrying `calendar:configure`, on 1 of `ago_chat`'s 4 currently-live sites. `role_assignment_projections`
holds **77 rows** (60 carrying `calendar:configure`) for **74 distinct tenants**.

**Do the two numbers agree?** For what is live right now: yes. The one real operator who currently holds
`calendar:configure` has a projection row, and it is current (`updated_at` matches this backfill run,
confirmed by cross-referencing `external_subject_id` and `tenant_id` — the projection's own
`operator_id` is a value `ago_calendar` derives itself, not a copy of `ago_chat`'s internal operator row
id, which cost one wrong join before this was found). No live tenant with a real calendar grant is
missing its projection today.

**A second, different finding, filed separately.** Of the 74 distinct tenants the projection table holds
an opinion about, only 4 still exist in `ago_chat` — the other **70 (≈95%) are gone**, deleted by
`DemoTenantExpiryJob`'s raw `DELETE FROM sites`, which `personal-data.md`'s own existing row already
documents as never reaching the outbox. Nothing ever told `ago_calendar` those tenants were erased, so
their role-assignment rows simply stay. This is not what `22-16`/`22-28` were counting — filed as its own
item, `25-82`, per CLAUDE.md rule 14.
