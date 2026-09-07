# the backfill host could not be built into an image

- **Stage**: 22
- **Status**: done (2026-09-04), `ago-chat@44355d3`. Written retrospectively on 2026-09-07 — see
  `22-29`, which also covers `22-27`.
- **Found**: 2026-09-04, running `22-16`'s backfill on the node for the first time.
- **Note on the record**: this item never had a GitHub issue, in either repository. It exists only as
  the commit below. That is why nothing in `ago-root`'s queue ever named it, and why it is being
  written up three days after it shipped rather than at the time.

## Written retrospectively, from the commit alone

There is no issue to read and no other document that mentions this by number. Everything below comes
from `ago-chat@44355d3` — `fix(22-26): the backfill host can be built into an image, which it could
not` — and from reading the Dockerfile it changed. Nothing here is inferred beyond what that commit
message and its diff say.

## What was actually true

`22-16` shipped `Ago.Chat.RoleAssignmentBackfill` as a one-shot host meant to be run on the node. Its
project file existed in the solution and the arch-test suite passed — `17-12` had already added a
reference-boundary test for this project, and it was green, because the test builds the solution, not
the container image.

`ago-chat`'s `Dockerfile` restores projects from an explicit, enumerated list of `COPY` lines rather
than a glob, so the restore layer can cache per project file. `Ago.Chat.RoleAssignmentBackfill` was
never added to that list. Building the image failed with:

```
MSBUILD : error MSB1009: Project file does not exist.
```

— a message that names neither the missing project nor the fact that it is absent from the Dockerfile.
The host existed, compiled, and passed every test in the suite, and there was still no way to package
it into something that could run on the cluster.

## Why nothing caught it before this

The commit message states this plainly: the suite builds the solution, not the image. CI at the time
built images from only the four names hardcoded in `build-images.sh` (`Ago.Chat.Api`,
`Ago.Chat.Worker`, `Ago.Chat.Webhooks`, `Ago.Chat.Migrator`) — the backfill was not among them either,
which is `22-27`'s half of the same afternoon. `17-12`'s architecture test proved the host had a
correct rule about *what it may depend on*; it said nothing about whether the host could be *delivered*
at all.

## What shipped

`ago-chat@44355d3` — `fix(22-26): the backfill host can be built into an image, which it could not` —
adds one `COPY` line for `Ago.Chat.RoleAssignmentBackfill.csproj` to the Dockerfile's restore layer,
in the same enumerated style as the four hosts already there. The commit records that it was proven on
the node before landing: with the line added, the image built and was tagged, and the checkout used to
prove it was restored to clean afterward.

## What is not recoverable

Nothing about *why* the project was left off the original list survives beyond "it was". `22-16`'s own
file closed with "the backfill still has to be run on the node" as its stated remainder, which reads,
in hindsight, as if running it were the only thing left — the commit message here is explicit that this
was not the remainder anyone expected. No note anywhere records whether the omission was noticed and
deferred, or simply never checked.

## Out of scope

- `22-27` — the other two reasons the same run failed: absence from `build-images.sh`, and the
  `postgres-ingress` NetworkPolicy refusing the pod's connection to the database. Filed separately
  because it shipped as a separate `ago-deploy` commit under its own number.
- Re-running the backfill or counting its effect — `22-28`.

## Done when

- [x] The record exists: what the gap was, why nothing caught it, what shipped, and that no GitHub
      issue for this number ever existed.
