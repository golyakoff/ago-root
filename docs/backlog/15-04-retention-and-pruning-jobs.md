# Data retention: the pruning mechanism, not the tier policy

- **Stage**: 15
- **Status**: ready — deliberately scoped to the *mechanism* (operational pruning of rows nothing reads
  any more); the product-facing question of how long a free-tier tenant's chat history is kept stays
  with `13-05-usage-cap-entitlements.md`, which is blocked on exactly that business decision
- **Depends on**: nothing — every table involved already exists

## Goal

Nothing on the deployment grows without bound. Today several things do: `outbox` rows are never
deleted after publication, `messages` partitions are created and never dropped, and the webhook
delivery log accumulates one row per attempt forever. On a 2Gi Postgres volume on a one-node VPS, an
unbounded table is not a hygiene issue, it is an outage with a delay fuse. After this item each of
those has something that removes what is no longer needed, on a schedule, with the removal itself
observable.

## Context to read first

`docs/backlog/2-01-platform-outbox-inbox-and-messaging-port.md`'s out-of-scope note — "outbox row
pruning/retention: `messaging.md` names it as a maintenance concern but no stage commits" — this item
is that stage. `docs/backlog/2-06-messages-partitioning.md`'s out-of-scope note — "retention / dropping
old partitions: `data-model.md` names `DROP` as the cheap-retention mechanism" — same. `architecture/
data-model.md`'s partitioning section for how partitions are created today and what dropping one
actually costs. `docs/backlog/13-05-usage-cap-entitlements.md` in full, especially its open question on
free-tier history retention — the boundary this item must not cross. `docs/backlog/6-03-webhook-
registration-and-delivery-history.md` — the delivery log exists because a webhook system without one is
unsupportable, so pruning it has a floor: it must stay useful to a tenant debugging yesterday's failure.
`architecture/concurrency.md` and `Ago.Chat.Worker`'s existing jobs (`OutboxDispatcher`,
`ConversationAssignmentJob`) — the shape a scheduled maintenance job takes here already exists; do not
invent a second one.

## Scope

- Prune published `outbox` rows past a short operational window (long enough that the window is itself
  a debugging aid, short enough that the table stays small). Deletion in bounded batches — a single
  unbounded `DELETE` on a hot table is its own incident.
- Drop `messages` partitions past a retention horizon, and create future ones ahead of time.
  **Changed by `adr/0031` (2026-08-25)**: partitions are per retention class *and* month, so a drop is
  per class, and nothing may be dropped before its archive object is confirmed written (`13-06` owns
  the archive step). This item still owns the mechanism; the grid it maintains simply gained a
  dimension, and the drop gained a precondition. The horizon
  here is an **operational default**, chosen so the disk survives, and written down as replaceable by
  whatever number `13-05` eventually decides per tier — the mechanism must take the window as
  configuration, not bake a constant into a migration.
- Prune the webhook delivery log, keeping the window `6-03`'s own support argument requires.
- Whatever equivalent exists for `inbox`/idempotency rows — check rather than assume; an idempotency
  table that never forgets is the same shape of problem.
- Each job emits what it did (rows removed, partitions dropped, duration) as a metric, so `15-03` can
  alert when a prune stops running — a maintenance job that silently stopped is indistinguishable from
  one that has nothing to do.
- Verified against a database deliberately filled past the horizon, not against an empty one. A prune
  that has only ever run on a table with nothing to prune has not been tested.

## Out of scope

- **Free-tier history retention as a product limit** — `13-05`, blocked on the author's own decision
  between a rolling time window and a message-count cap. This item builds a configurable mechanism and
  sets an operational default; it does not choose the tier policy, and it must not quietly become that
  decision by shipping a number the product then inherits.
- Attachment/object-storage lifecycle — `5-04`'s orphan sweeper already covers unreferenced objects,
  and deleting attachments belonging to *live* conversations is a retention-policy question (`13-05`),
  not a maintenance one.
- Archival to cold storage before deletion — nothing asks for it, and it would need a destination,
  a format, and a reason.
- Prometheus/Jaeger data retention — `7-03` already reasons about that on its own terms.

## Done when

- [ ] Every unbounded table named above has a bounded-batch prune or a partition drop, running on a
      schedule, in the existing Worker job shape.
- [ ] Every window is configuration, not a constant, and its current value is documented as an
      operational default that `13-05` may override.
- [ ] Each job's work is visible as a metric, and `15-03` has a rule for "this stopped running".
- [ ] Tested against data actually past the horizon, including at least one real partition drop.
- [ ] `2-01`'s and `2-06`'s out-of-scope notes are updated to point here.

## Open questions

None for the mechanism. The one genuinely open question in this area — free-tier history retention —
belongs to `13-05` and is deliberately left there rather than answered here as a side effect.

Note added 2026-08-25: `architecture/personal-data.md` records that message content is the bulk of the
personal data here and the part that cannot be minimised by choosing fields, which makes this item's
machinery the mechanism behind the strongest privacy lever available — not only a way to keep a 2Gi
volume alive. The scope boundary above is unchanged; the reason to build it well is larger.
