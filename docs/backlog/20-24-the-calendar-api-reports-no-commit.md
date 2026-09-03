# Make `Ago.Calendar.Api` report the commit it was built from

- **Stage**: 20
- **Status**: ready
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

- [ ] `https://calendar-api.<domain>/healthz/version` reports the commit the image was built from.
- [ ] `smoke.sh`'s two calendar `SKIP`s are gone and the suite is green against the live deployment.
- [ ] Proven by mismatch rather than by agreement: point the overlay at a different tag, show the
      check goes red, put it back.
- [ ] The `/healthz/ready` question is answered in writing, either way.
