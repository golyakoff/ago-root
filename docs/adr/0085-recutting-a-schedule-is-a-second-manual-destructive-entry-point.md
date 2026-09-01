# ADR-0085: Re-cutting an already-materialised horizon is a second, manual, destructive entry point

- **Status**: Accepted
- **Date**: 2026-09-01
- **Stage**: 20 (`20-16`, extends `20-14`/`adr/0053`)

## Context

`adr/0053` established that the background materialisation job is insert-only — it never updates or
deletes, only fills empty business-local days. That is what makes two concurrent replicas safe, what
makes a repeated run safe, and what makes a tenant's manual edits and every customer's booking durable
against it forever. That is the actual thing "insert-only" was protecting: an unattended job running on
a timer against every calendar in the deployment must never originate a destructive write, because
nobody is watching when it runs, and a bug in it would be a silent, tenant-wide loss discovered only
after the fact.

`20-14` gave each worker's schedule a `MaterializeFrom` cursor that only moves forward — correct for the
job, but it created a real defect: a tenant who fixes a wrong template sees nothing change for up to 180
days, because every day in that window is already cut and the job never revisits it.

## Decision

**The job stays insert-only, unconditionally — this item changes none of it.** A second, structurally
separate path is added: `WorkerSchedule.RecutFrom`, whose only precondition is the exact logical
complement of the forward-only trio's (`ReconfigureWeekly`/`ReconfigureCycle`/`AdvanceCursor`) — it
accepts only an actual regression. It is reachable from exactly one place: a console screen that
previews what would be deleted, takes a per-booking keep-or-cancel decision, and only then fires a
synchronous, in-request re-cut.

The distinction is real, not a loophole, because of *who* runs each path and *when*: the job runs
unattended, on a timer, against every calendar that exists — a destructive write there is a surprise
nobody chose. The re-cut runs once, for one worker, from a button a human just pressed, after being
shown exactly what disappears. "Insert-only" was never a claim that this product can never delete a
slot; it was a claim that the thing running unattended cannot. `adr/0053`'s own alternatives-considered
section already drew this line for a different case (rejecting a distributed lock as guarding "an
outcome the exclusion constraint already makes impossible") — this item is the mirror image: a decision
the job structurally cannot make safely on its own, because it has no way to ask "is this booking OK to
lose."

**A day holding a kept booking is left whole, never partially re-cut around it** — `adr/0049`'s
exclusion constraint is real physics here, not a preference: a kept row and a newly-cut slot covering
the same time would collide at the database level regardless of what application code intends, so the
handler skips the whole day rather than attempting an insert the database would refuse anyway.

**Cancellation inside a re-cut goes through the ordinary `CancelBookingHandler`, never a raw delete** —
a cancelled booking's row still exists afterward, marked `Cancelled`, exactly like any other
cancellation in this product.

**A staleness fingerprint over the booking set in range is compared fresh at confirm time; a mismatch
refuses the whole operation.** A booking created in the gap between preview and confirm must never have
a decision silently applied to a world that no longer matches what the operator saw.

## Consequences

- **Positive**: `WorkerSchedule` has two ways to write `MaterializeFrom`, with disjoint preconditions,
  so no caller reaches the wrong one by accident — there is no shared "unlocked" flag either could slip
  past.
- **Positive**: the exclusion constraint, not application logic alone, is what actually prevents a
  re-cut from destroying a kept booking — the guarantee holds even against a future bug in the
  handler's own day-skip logic, because the database itself would refuse the conflicting insert.
- **Negative, named plainly**: a `NoShow` row cannot be decided at all (`Event.Cancel` refuses a
  terminal state) and so always forces its day to be skipped — a tenant who wants to reclaim a day held
  hostage only by an old no-show has no path to do so through this item. A real, narrow gap, not
  addressed here.
- **Negative**: the staleness check is a fingerprint, not a per-booking version — cheap, and it can
  refuse spuriously when an unrelated booking in the range merely changed status between preview and
  confirm, for an operation the item's own scope calls rare by design.

## Alternatives considered

- **Widening the background job itself to delete-and-regenerate a changed day.** Rejected — it is
  exactly the "regenerate the whole window every run, upserting" alternative `adr/0053` already
  rejected, for the identical reason: it turns every future edit to the job into a place a bug can
  destroy a tenant's data unattended.
- **A flag on `WorkerSchedule` marking "re-cut on next run", consumed by the job.** Rejected — it
  reintroduces the declarative-exception-table shape `adr/0053`'s own alternatives-considered section
  already rejected for day-off handling, and a delayed unattended destructive write is still an
  unattended destructive write.
- **A boolean parameter on `AdvanceCursor`** (e.g. `allowRegression: true`) instead of a separate
  `RecutFrom` method. Rejected: one method whose contract flips on an argument is reachable by a future
  caller copying an existing call site and flipping the flag without meaning to; a second method with
  the opposite precondition can only be reached by a caller deliberately asking for a regression.
