# ADR-0056: Schema migrations are a separate deployable that runs before the hosts

- **Status**: Accepted
- **Date**: 2026-08-26
- **Stage**: 8 (deployment), with consequences for 13 and 15
- **Specifies**: `backlog/8-08-schema-migrator-as-a-deployable.md` — this ADR is the specification;
  read it rather than guessing, the way `adr/0048` served `17-08`.

## Context

**Nothing in this system applies a migration.** There is no `Database.Migrate()` anywhere in
`ago-chat/src` — verified, not assumed. Schema changes reach an environment when a human runs
`dotnet ef database update` from a developer machine, and the runbooks say so.

That is not a neutral status quo, because it has already failed:

> On 2026-08-25 a redeploy followed `public-deploy.md`, skipped step 9 (migrations) because a step
> marked "done" does not read like a step, and left the API running against a schema three migrations
> behind. **Every page still returned 200 while every query loading a `Site` failed.**

The shape of that failure is the argument. A missing migration does not stop the deployment, does not
fail a readiness probe, and does not show up as an error rate on the surface anybody watches. It
shows up as a subset of queries failing while the process is, by every signal the platform collects,
healthy. `redeploy.md` now carries the step as a procedure rather than a record, which reduces the
chance of the same mistake and does not change what happens when it is made anyway.

A second, quieter problem sits underneath. Because the same connection string serves both the
application and the schema changes, **the runtime role holds DDL rights it never uses**. Nothing
depends on that today; it is simply a privilege nobody chose.

## Decision

**A migration is applied by its own deployable, which runs to completion before any host starts, and
by nothing else.**

### It is a host, split by failure profile

`Ago.Chat.Migrator`, a console host alongside `Ago.Chat.Api`, `Ago.Chat.Worker` and
`Ago.Chat.Webhooks`. `adr/0013` splits those three by failure profile rather than by domain, and this
is the same cut taken one step further: applying DDL fails differently from serving traffic, needs
different privileges, and must be able to stop a deploy.

It references `Ago.Chat.Infrastructure.Postgres` and nothing above it. It contains no use case, no
endpoint and no domain logic — it opens a connection, applies what is pending, reports what it did,
and exits.

### It runs to completion; it is not a service

In Kubernetes this is a `Job`, not a `Deployment`. A migrator that stays running has no meaning: the
question it answers is "is the schema at the version this release expects", and that question has an
answer and then it is over. **The exit code is the deliverable** — zero when the schema is at the
expected version (whether or not anything was applied), non-zero when it is not, and a non-zero exit
must stop the deploy rather than be retried into a crash loop.

Idempotency needs no new mechanism: `__EFMigrationsHistory` already makes a repeated run a no-op,
which is what lets the same Job run on every deploy rather than only on the deploys that need it.

### The migrations themselves do not move

They stay in `Ago.Chat.Infrastructure.Postgres/Migrations`, next to the `DbContext` that generates
them. The migrator *references* that assembly. Moving migrations into the migrator project would put
them somewhere `dotnet ef migrations add` does not naturally target and would separate a migration
from the model snapshot it is generated against — a cost paid on every schema change, to buy nothing.

### One migrator per product, and no shared one

`Ago.Calendar` gets `Ago.Calendar.Migrator` when it needs one. A single shared migrator would have to
reference both products' `DbContext` types, and **the platform must never reference a product**
(`CLAUDE.md`, `adr/0012`) — the repositories make it impossible, which is the point of them.

The *mechanism* — "apply pending migrations for `TDbContext`, report, exit" — is a plausible
`Ago.Platform.*` type later. It does not qualify now: `clean-architecture.md`'s rules refuse a
platform abstraction with one caller, and premature generalisation is the platform layer's
characteristic failure. **The trigger is `Ago.Calendar.Migrator` existing**, at which point there are
two callers and the shared part is whatever both turn out to have needed.

### The name carries no technology

`Ago.Chat.Migrator`, not `…EfMigrator` or `ago-db-ef-migrator`. EF Core is how it is implemented
today (`adr/0004`), and the name should survive that changing. The existing hosts are named for what
they are for, not what they are built with, and this is the same rule.

## Consequences

**Expand/contract stops being optional, and this is the real cost.** Once the schema is applied
before the hosts roll, there is a window — the whole rolling deploy — in which pods running the
*previous* release are talking to the *new* schema. A migration that drops or renames a column that
the old code still selects breaks production for the length of that window. So a schema change
becomes two releases: add and backfill first, remove only once nothing reads it. That is a real
discipline and it is being adopted deliberately, not discovered later.

**The permission split becomes possible, and is not claimed here.** With DDL confined to one
deployable, the runtime role can be narrowed to DML — a genuine reduction, since an application
compromise then cannot alter the schema. It needs its own work (two roles, two connection strings,
and the grants to go with them) and belongs with `17-03`'s secret inventory rather than being folded
in silently.

**Rollback is a restore, not a `Down()`.** EF generates `Down()` methods and this project has never
run one, so claiming reversibility would be false. A migration that turns out to be wrong is handled
by `15-02`'s restore path. Making `Down()` trustworthy is a separate decision with its own cost, and
this ADR does not take it.

**A slow migration now blocks the deploy rather than being run at leisure.** Today a human picks the
moment. A Job in the deploy sequence does not, so a migration that rewrites a large table stops the
release for as long as it takes. The tables where that becomes real are `messages` and its partitions
— `13-06` and `15-04` territory — and the mitigation is the same expand/contract discipline above.

**Local development is unchanged in shape.** The runbook step stays; the compose loop may run the
same image instead, which is the smaller of the two ways to keep local and deployed honest.

## Alternatives considered

**Leave it as a documented deploy step.** Rejected on evidence: it was a documented deploy step on
2026-08-25 and it was skipped, and the resulting failure was invisible to every health signal. A
procedure whose only enforcement is that somebody reads it has already been tried here.

**Apply migrations at host startup (`Database.Migrate()` in each `Program.cs`).** The obvious
alternative, and the common one. Rejected on three counts. The API runs three replicas, so three pods
would race to apply the same migration — recent EF Core takes an advisory lock, so this is safe
rather than corrupting, but the losers block on startup and can miss their readiness deadline while
waiting. `Ago.Chat.Worker` and `Ago.Chat.Webhooks` would each do it too, so three hosts would carry
a capability only one of them needs. And it welds "may I serve traffic" to "may I change the schema",
which is exactly the coupling the permission consequence above exists to break.

**A migration step inside `redeploy.sh` rather than a deployable.** Closer to workable, and rejected
for a narrower reason: it works only for deploys that go through that script. A `Job` in the manifest
set is applied by whatever applies the manifests, including a cluster rebuilt from scratch during
`15-02`'s restore drill, where a shell script on somebody's machine is not in the loop.

## Open questions

**How the ordering is enforced.** Kustomize has no native "this Job before those Deployments", so
the candidates are an init container on each host that waits for the expected schema version, an
ordering step in the deploy script, or both. The init-container form is the one that survives a
cluster rebuilt without the script — and it needs the hosts to be able to *state* the version they
expect, which may be the more interesting half of the item.

**Whether seeding joins the migrator.** The runbooks pair migrations with a seed step. They are
different things — one is schema, one is data, and only one is safe to re-run against a live
database — but they share a moment in the deploy. The item decides and records which.
