# Provider switch by configuration, proven by a CI matrix - not by hand

- **Stage**: 9
- **Status**: ready
- **Depends on**: `9-01-kafka-messaging-adapter.md`, `9-02-mysql-persistence-adapter.md` - both
  adapters must exist before there is a second combination to switch to or a matrix to run

## Goal

`Messaging:Provider` (`rabbitmq|kafka`) and `Persistence:Provider` (`postgres|mysql`) - already named
as the intended shape in `clean-architecture.md`'s Hosts rule - actually select the whole system's
wiring in every `Ago.Chat.*` host, with zero source changes in `Domain` or `Application` required to
flip either one. `ago-chat`'s CI runs the full test suite twice, once per named combination, on every
push - so "the ports are real" is a fact a reviewer can see go green in Actions, not a claim in a
report. This is `roadmap.md`'s own Stage 9 Done-when, delivered directly.

## Context to read first

`docs/architecture/clean-architecture.md`'s Hosts section - `AddPostgresPersistence()`/
`AddRabbitMqMessaging()`-style extension methods already named as the intended seam, selected by
configuration in the one place (`Ago.Chat.Module`/host `Program.cs`) allowed to know concrete
implementations. `docs/adr/0002-clean-architecture-layering.md` - "the Stage 9 provider swap becomes a
configuration change" is this ADR's own stated proof of the dependency rule; this item is where that
sentence is either confirmed true or found not to be, honestly. `docs/backlog/0-04-ci-pipeline.md` -
its own Out of scope line ("The provider matrix (Kafka, MySQL) - Stage 9 adds it") is this item's
mandate; read its Scope for the existing workflow shape (format check before build, Testcontainers on
`ubuntu-latest`, `.trx` artifacts) this item extends rather than replaces. `docs/architecture/
repositories.md`'s versioning section - if either adapter needs a platform package version bump to be
consumable from `ago-chat`, that already has to have happened in `9-01`/`9-02`; this item only wires
selection, it does not publish anything new.

## Scope

- `Ago.Chat.Module`'s DI composition root (and each host's `Program.cs`, wherever the current wiring
  actually lives - confirm before writing): read `Messaging:Provider` and `Persistence:Provider` from
  configuration at startup, call the matching `Add*` extension method from whichever adapter project
  matches, and fail startup with a clear error on an unrecognised value - the same "a typo must fail
  the pod, not silently disable a feature" rule `naming-and-structure.md` already states for every
  options class.
- `appsettings.json`/`appsettings.Local.json.example` (or wherever provider selection belongs per the
  existing configuration convention) gain the two keys, defaulting to `postgres`/`rabbitmq` - the
  combination every other backlog item so far has been built and tested against, so nothing changes by
  default for a session that never touches these keys.
- `deploy/`'s local compose/Kustomize overlays: confirm (and adjust only if genuinely necessary) that
  the default local stack still boots as `postgres`/`rabbitmq` unchanged - this item does not add MySQL
  or Kafka containers to the everyday local loop, only makes switching to them possible; a second,
  clearly-named overlay or compose profile for the alternate combination is in scope if the simplest
  way to prove the switch works locally needs one, but is not required if CI's own matrix already
  proves it without one.
- CI (`ago-chat`'s GitHub Actions workflow): a job matrix with (at minimum) two legs - the default
  combination (`postgres`/`rabbitmq`) and the alternate combination (`mysql`/`kafka`) - each running the
  full existing suite (`Ago.Chat.Domain.Tests`, `Ago.Chat.Application.Tests`,
  `Ago.Chat.Architecture.Tests`, `Ago.Chat.Integration.Tests`, `Ago.Chat.Concurrency.Tests`) with the
  matrix leg's `Messaging:Provider`/`Persistence:Provider` set, against real Testcontainers instances of
  whichever broker/database that leg names. State explicitly, in this file's own scope note and in the
  workflow's own comments, that the two "mixed" combinations (`postgres`/`kafka`, `mysql`/`rabbitmq`)
  are deliberately not run - `roadmap.md`'s own Done-when names "both provider combinations," not all
  four, and running all four would be scope this item was not asked for; if the author later wants the
  stronger, cross-combination proof (persistence and messaging are independently swappable, not just
  the two combinations that happen to be named), that is a follow-up backlog item, not a silent
  expansion of this one.
- A short new section in `docs/runbooks/local-dev.md` (or a new file if the existing runbook does not
  fit) - "running against the alternate provider combination locally" - the same "a session with no
  memory can repeat this" bar every other runbook entry is held to.

## Out of scope

- Building either adapter - `9-01`/`9-02`, prerequisites for this item.
- Making the alternate combination the default anywhere, in CI or locally - the point is that both
  combinations are proven, not that one replaces the other.
- The mixed-combination matrix legs named above - explicitly deferred, not forgotten, per the Scope
  note's own reasoning.
- Any change to `Domain` or `Application` - if wiring the switch turns out to need one, that is this
  item failing its own Done-when, not a change to make quietly and move on; it becomes a reported
  finding for `9-04` and a blocked status here until resolved.

## Done when

- [ ] Setting `Messaging:Provider=kafka` and `Persistence:Provider=mysql` (via configuration, no source
      edit) brings up `Ago.Chat.Api`/`Worker`/`Webhooks` against a real Kafka and a real MySQL instead of
      RabbitMQ/Postgres, verified live locally at least once (not just in CI) - the same "verified means
      actually run" bar `local-cluster`/`k8s-local.md` already hold every other bring-up to.
- [ ] `git diff` of the branch that adds this switch touches no file under `Ago.Chat.Domain/` or
      `Ago.Chat.Application/` beyond this item's own `Depends on` adapters' own layers - the literal
      proof of `roadmap.md`'s "zero changes in Domain or Application" line, checked and stated, not
      assumed.
- [ ] `ago-chat`'s CI workflow runs the full suite twice per push, once per named combination, both green
      on the same commit - visible in Actions as two distinct, clearly-labelled jobs, not one job that
      silently only ran one combination.
- [ ] `docs/architecture/clean-architecture.md`'s Hosts section double-checked against what was actually
      built (the exact extension-method names, the exact configuration keys); corrected in this same
      change if it drifted from the earlier, forward-looking wording.
- [ ] `docs/runbooks/local-dev.md` updated with the alternate-combination bring-up steps.

## Open questions

None. The two combinations to prove are named directly by `roadmap.md`'s own Done-when; everything
else here is wiring against ports `9-01`/`9-02` already implement.
