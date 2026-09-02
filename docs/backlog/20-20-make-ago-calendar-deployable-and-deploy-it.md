# Make AGO Calendar deployable, and deploy it

- **Stage**: 20
- **Status**: ready — **and this is the largest single gap between the product as built and the product
  as usable.** Nothing else in Stage 20 can be verified by hand until this lands.
- **Found**: 2026-09-02, by asking where AGO Calendar runs and discovering the answer is nowhere.

## The gap, counted rather than characterised

**Fifteen Stage 20 items are marked done** (`20-01`…`20-04`, `20-06`, `20-08`…`20-16`, `20-18`), along
with `adr/0049`, `0053`, `0059`, `0064`, `0083`–`0088` and `0090`. Every one of them merged, tested and
green.

**None of them runs anywhere.** Checked across the whole cluster rather than one namespace: seven
namespaces, twenty-two deployments, zero statefulsets, and the live Postgres holds exactly `ago_chat`,
`keycloak` and `postgres`. No calendar API, no calendar console, no calendar database.

It is not that a deploy was forgotten. **AGO Calendar has never been deployable**, and no backlog item
ever covered making it so:

- `ago-deploy` has never contained a calendar manifest — not on `main`, not on any branch, ever
  (`git log --all --diff-filter=A -- '*calendar*'` is empty).
- `ago-calendar` contains **no Dockerfile at all**, for either host. There is nothing to build an
  image from.
- Its CI **builds and tests only** — restore, vulnerability check, format, build, test, publish test
  results. There is no image-publishing job, so `adr/0047`'s commit-SHA-tagged images do not exist for
  this product.
- There is **no migrator project**, and the Api does not migrate on startup. `adr/0056` requires
  migrations to be a separate deployable that runs before the hosts, and Calendar has neither that nor
  the alternative. **Its schema has no way to come into existence outside a test fixture.**

`ago-calendar-console` is further along than the backend: it has a `Dockerfile` already. That
asymmetry is worth knowing when scoping — the console is closer to shippable than the thing it talks to.

## Why this is urgent rather than merely missing

The first tenant's business is scheduling. `20-20` is not "deploy another service"; it is the
difference between a product and fifteen merged pull requests.

## What this must produce

Grouped by repository, because the work splits cleanly and the first half has no value without the
second.

**In `ago-calendar` — make it buildable and migratable:**

- A `Dockerfile` per host (`Ago.Calendar.Api`, `Ago.Calendar.Worker`), following `ago-chat`'s own
  chiselled-base shape (`8-00`) rather than inventing a second one.
- **A migrator deployable** — `adr/0056`, not negotiable and currently absent. `Ago.Chat.Migrator`
  (`8-08`) is the worked example, including its own rule that the migrator's image moves with the
  hosts and never independently.
- A CI job that builds and publishes both hosts plus the migrator to GHCR under commit-SHA tags,
  matching `adr/0047`. Trivy scanning included, as `ago-chat`'s does.

**In `ago-calendar-console`** — confirm its CI publishes an image the same way (`15-07`/`adr/0051`: a
frontend image takes no environment input from its build command).

**In `ago-deploy` — make it run:**

- Manifests for both hosts and the migrator Job, with the same runtime hardening every other workload
  carries (`17-05`/`adr/0054`) rather than a softer profile because it is new.
- The database. **Recommended: a separate `ago_calendar` database on the existing Postgres instance**,
  not a second instance — one node, one small tenant, and `adr/0026`'s sizing. Note this needs no
  backup change at all: `backup.sh` enumerates databases as of 2026-09-02 precisely so a new one cannot
  be silently missed.
- Gateway routes and TLS for the calendar API and console hostnames (`adr/0014`, `edge.md`).
- Keycloak wiring — Calendar resolves its own `Operator` from the same realm (`adr/0027`/`0088`), so it
  needs its own client/audience rather than borrowing Chat's.
- Overlay pins for every new image, all moving together with the migrator (`8-08`).
- `smoke.sh` coverage: at minimum the calendar API answers, reports its commit, and its image tag
  matches the commit inside the binary — the same three checks every other host already gets.

## Decisions this forces, named rather than left to the implementer

- **One Postgres instance or two.** Recommended above; record the choice.
- **One namespace or its own.** Everything currently lives in `ago-chat`, which is already a
  misleading name for a namespace holding Keycloak, MinIO and Grafana. Adding Calendar to it makes the
  name worse; a second namespace costs routing and secret duplication.
- **Whether Calendar's Worker is needed on day one.** It exists as a host; what it runs and whether the
  first tenant's flows depend on it should be checked rather than assumed, because one fewer deployable
  is materially less to get right before a launch.

Any of these that turns out to be genuinely contested becomes an ADR; none is assumed to be.

## Out of scope

- The public booking API, which ships disabled and stays disabled — its exposure is its own decision
  (`20-19` and `adr/0090`'s own context).
- Operator-created bookings, phone correction, customer search, reschedule, visit outcomes. All of
  those are separate items that `adr/0090` decides the shape of. **They are also unverifiable by hand
  until this item lands**, which is the argument for doing this first.
- Any performance claim about the calendar. Rule 7 unchanged.

## Done when

- [ ] Both calendar hosts and the migrator build into commit-SHA-tagged images published by CI, with
      no manual step.
- [ ] The migrator runs before the hosts and creates the schema on an empty database, proven by doing
      it rather than by reading the manifest.
- [ ] A tenant can reach the calendar console over TLS at its own hostname and sign in against the
      existing realm.
- [ ] `smoke.sh` covers the calendar API with the same three checks the other hosts get, and it is
      green.
- [ ] One backup taken **after** the calendar database exists is shown to contain it —
      `databases_dumped=` in the manifest names it. This is the check that proves the 2026-09-02
      enumeration change did what it was for; it is cheap and it closes the author's own stated worst
      case.
- [ ] A restore of that backup into the scratch target brings the calendar database back with its rows
      — the drill, repeated once with the new database present.
- [ ] `docs/architecture/repositories.md` and the deploy runbooks describe the calendar hosts, because
      a deployment nobody documented is one the next session rediscovers.

## Open questions

- **Does the first tenant need the calendar console, the booking widget, or both?** The console is how
  she manages her schedule; the widget is how her clients book. The launch needs both, but they can
  land in either order, and knowing which she will set up first changes what to verify first.
- **What happens to the demo stand's existing tenants** when a second product appears in the same
  realm — nothing, probably, but "probably" is what this project's own `5-18` was made of.
