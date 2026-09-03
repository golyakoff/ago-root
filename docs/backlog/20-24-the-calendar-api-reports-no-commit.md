# Make `Ago.Calendar.Api` report the commit it was built from

- **Stage**: 20
- **Status**: done (2026-09-03)
- **Found**: 2026-09-03, landing `20-20` — the calendar's first deploy reported `37 passed, 0 failed`
  with these two checks among the skips.

## The gap

`Ago.Calendar.Api` maps no `/healthz/version`. It maps no health route at all — only a bare `GET /`
returning the loaded module's name. Every other host here reports its build commit, and `smoke.sh`
uses that for two checks:

- the host reports its commit (it was built from a known source tree)
- the image tag matches the commit **inside the binary**

For the calendar API both are `SKIP`. They are skipped honestly rather than faked against `GET /`,
which carries no commit information to compare — but skipped is skipped.

## Why it matters more than a missing endpoint

`20-20` asked for "the same three checks every other host gets". One of three is real today, and the
two missing ones are exactly the pair that catches a **stale or mismatched image** — the manifest
pinning one commit while the running container is another. Nothing else in the suite would notice.

That failure is not hypothetical for this product: the calendar's API, worker, migrator and console
are pinned in the demo overlay and are required to move together (`8-08`). And it is not hypothetical
for this project either — `deploy.sh` exists because a console bundle once ran a week stale with
nobody able to say which commit was in it.

## What this must produce

- `/healthz/version` on `Ago.Calendar.Api`, in the shape `Ago.Chat.Api` already uses — the worked
  example, not a second convention.
- **Whether the calendar hosts also need `/healthz/ready` is a real question, not an assumed yes.**
  The API has Postgres and Redis behind it, and its probes currently hit `GET /`, which checks
  neither: the host can be serving while its dependencies are gone. Answer it rather than carry it.
- `smoke.sh`: replace the two `SKIP`s with the real checks.

## Done when

- [x] `https://calendar-api.<domain>/healthz/version` reports the commit the image was built from. —
      reports `8e3507fb…`, the commit that added the route.
- [x] `smoke.sh`'s two calendar `SKIP`s are gone and the suite is green against the live deployment.
      — `40 passed, 0 failed`.
- [x] Proven by mismatch rather than by agreement. — the pin was set to a tag the binary does not
      carry and the suite reported `calendar API image tag 000000000000 but the binary reports
      8e3507fb74c6 - the tag is lying about its contents`, then restored. Safe to do on a live demo
      because one replica with `maxUnavailable` rounding to zero cannot drop its serving pod for one
      that never becomes ready: the neighbouring check kept passing throughout, which is the evidence
      the service stayed up.
- [x] The `/healthz/ready` question is answered in writing, either way. — **yes, and implemented.**
      The API has Postgres and Redis behind it and its probes hit `GET /`, which checks neither; a pod
      could serve while both were gone. `PostgresHealthCheck` went to `Infrastructure.Postgres` rather
      than the host: `IHealthCheck` is already the port, and a health check in the composition root
      reaching for a `DbContext` cannot be tested without a database.

## Outcome

Closed 2026-09-03, same day it was filed, because `20-20` had already wired the
`-p:SourceRevisionId` mechanism into this repository's Dockerfile and CI — it was working and simply
unread. The item assumed a Dockerfile and CI change; neither was needed.

**Liveness was deliberately kept separate from readiness.** `/healthz/live` answers whether the
process is alive and nothing else. A liveness probe wired to `/healthz/ready` restarts the pod every
time Postgres blinks, which is the one response guaranteed not to help.

**Three changes had to land in one commit** on the `ago-deploy` side — the smoke checks, the image
pin and the probes. `/healthz/ready` exists in no image built before `8e3507fb`, so repointing probes
without moving the pin fails every probe and takes the deployment down; and landing the smoke change
before `ago-calendar`'s half would have turned the suite red against the image then running. That
last one is rule 15's "first breaks it, second fixes it" in its live form, which is why
`ago-calendar#26` merged first and this waited on its `publish-images` job.
