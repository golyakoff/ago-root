# A migration is applied by its own deployable, before anything else starts

- **Stage**: 8 — deployment. Filed 2026-08-26 (author's proposal, argued in session).
- **Status**: ready
- **Depends on**: nothing. `adr/0056` is the specification; read it rather than this summary, the way
  `17-08` read `adr/0048`.

## Goal

`Ago.Chat.Migrator` exists, runs to completion before the hosts start, and a deploy that cannot apply
its migrations stops instead of proceeding.

## Why, from an incident rather than a principle

There is **no `Database.Migrate()` anywhere in `ago-chat/src`** — schema changes reach an environment
because a human runs `dotnet ef database update`. On 2026-08-25 a redeploy skipped that step, and
`public-deploy.md` records what followed: the API ran against a schema three migrations behind, and
**every page returned 200 while every query loading a `Site` failed.**

That shape is the argument. A missing migration does not fail a probe, does not fail the deploy, and
does not move any error rate anybody watches. `redeploy.md` now carries the step as a procedure,
which lowers the chance of repeating the mistake and changes nothing about what happens when it is
repeated anyway.

## Scope

- **`Ago.Chat.Migrator`** — a console host next to `Api`/`Worker`/`Webhooks`, referencing
  `Ago.Chat.Infrastructure.Postgres` and nothing above it. No endpoint, no use case, no domain logic.
- **The exit code is the deliverable.** Zero when the schema is at the version this release expects;
  non-zero when it is not. It must report what it applied — a migration that runs silently is the
  same operational problem as one that does not run.
- **Migrations stay where they are**, in `Infrastructure.Postgres/Migrations`. The migrator
  references that assembly (`adr/0056` says why moving them costs on every schema change and buys
  nothing).
- **A `Job` in `ago-deploy`, not a `Deployment`**, plus whatever makes the hosts wait for it. See the
  first open question — that choice is most of this item's difficulty.
- **A container image**, built and published the same way the other three hosts are (`adr/0047`,
  `15-06`), so a rollback names a SHA like everything else.
- **Local development stays coherent**: either the runbook step remains or the compose loop runs the
  same image. Decide which and change the runbook to match; the two must not disagree.

## Out of scope, deliberately

- **The DDL/DML privilege split.** It is the strongest *consequence* of this item and it is not this
  item: two roles, two connection strings and the grants belong with `17-03`'s secret inventory. Do
  not half-do it here.
- **Making `Down()` trustworthy.** This project has never run one. Forward-only is the honest
  position, and a bad migration is `15-02`'s restore path.
- **`Ago.Calendar.Migrator`.** It comes when Calendar needs one, and it is the trigger for asking
  whether the mechanism belongs in `Ago.Platform.*` — with one caller it does not
  (`clean-architecture.md`).
- **Retrofitting expand/contract onto existing migrations.** The discipline starts here; the history
  is not rewritten.

## Done when

- [ ] `Ago.Chat.Migrator` applies pending migrations against a real Postgres and exits zero, and
      exits non-zero on a migration that cannot be applied — both proven by a test, not by running it
      once.
- [ ] Running it twice in a row is a no-op the second time, proven rather than assumed from
      `__EFMigrationsHistory`.
- [ ] A host cannot start against a schema older than it expects — **demonstrated**, by starting one
      against a deliberately out-of-date database and showing it refuses rather than serving 200s.
      This is the criterion the item exists for; the others are how it is built.
- [ ] The image is published under a commit SHA like the other three, and `redeploy.md`'s migration
      step is replaced by whatever now performs it.
- [ ] An architecture test keeps `Database.Migrate()` out of the three serving hosts, so this cannot
      be quietly reintroduced at startup later.

## Open questions

**How ordering is enforced, and it is the interesting half.** Kustomize has no native "this Job
before those Deployments". The candidates are an init container on each host that waits for the
expected schema version, an ordering step in the deploy script, or both. The init-container form is
the one that survives a cluster rebuilt without the script — which is exactly what `15-02`'s restore
drill does — but it requires a host to be able to *state* the version it expects, and where that
number comes from is not obvious. Decide it in the item and record it in `adr/0056`.

**Whether seeding joins the migrator.** The runbooks pair migrations with a seed step. They are
different things — one is schema, one is data, and only one is safe to re-run against a live database
— but they share a moment in the deploy. Decide and record.

**What the migrator does when there is nothing to do.** Exiting zero is obvious; whether it should
also verify that the schema is not *ahead* of what this release knows about is not. A pod rolled back
to an older image against a newer schema is the expand/contract window, and it is legitimate — so a
check here would have to distinguish "ahead, and that is fine" from "ahead in a way that will break
me", which may not be answerable.
