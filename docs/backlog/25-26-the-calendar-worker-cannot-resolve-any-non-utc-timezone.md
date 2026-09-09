# 25-26 · The calendar worker cannot resolve any non-UTC timezone

- **Stage**: 25
- **Status**: done — `ago-calendar#54`, deployed and confirmed live
- **Depends on**: nothing
- **Found**: 2026-09-09, live — the author saved a worker's schedule, the readiness checklist stayed
  stuck on "Слоты сгенерированы в пределах горизонта" with no slots ever appearing

## What is actually true

`ago-calendar-worker`'s `AvailabilityMaterializationJob` fails for **every calendar whose time zone is
not UTC**, silently: `SystemWallClockResolver.Resolve` calls
`TimeZoneInfo.FindSystemTimeZoneById("Europe/Moscow")`, which throws
`TimeZoneNotFoundException` → `DirectoryNotFoundException: Could not find a part of the path
'/usr/share/zoneinfo/Europe/Moscow'`. The job logs the failure and skips the calendar
(`Calendar ... has a time zone this host cannot resolve; skipping it.`) rather than crashing — which
is why nothing paged anyone and the only visible symptom was a readiness checklist that never
advances.

**Root cause, measured directly, not assumed from documentation.** `ago-calendar`'s `Dockerfile` final
stage is `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled` — the same tag `ago-chat`'s own
Dockerfile uses, copied from it deliberately (`20-20`'s brief). Pulled both the plain and `-extra`
variants and inspected their filesystems (`docker create` + `docker export` + `tar -tv`): the plain
`chiseled` tag ships **zero** files under `/usr/share/zoneinfo`; `chiseled-extra` ships the full tzdata
tree, `Europe/Moscow` included. `ago-chat` never hit this because it never resolves an IANA zone
against the OS at all — grepped `ago-chat/src` for `FindSystemTimeZoneById` and found nothing; this
codebase's own convention (`CLAUDE.md`: UTC always, render in the caller's zone) means chat never
needed the host's own tzdata. `ago-calendar` is the exception: `SystemWallClockResolver` genuinely
converts instants to local wall-clock dates server-side, which is exactly what wall-clock scheduling
("we open at nine") requires.

Every calendar on this deployment that has ever used a non-UTC zone has silently never materialized a
single slot. `24-17` gives this deployment's real zones as a small, non-DST set — none of them is UTC.

## Fix

`Dockerfile`'s final stage moves to `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled-extra` —
confirmed to add exactly `/usr/share/zoneinfo` (and ICU) and nothing else, so the chiseled
no-shell/no-package-manager security property this base was chosen for in the first place is
unaffected.

## Where this is likely to go wrong

- **This is one Dockerfile for four hosts** (Api, Worker, Migrator, Provisioner) — the fix applies to
  all four by construction, and only the Worker's materialization path was ever observed failing, but
  the Api process could hit the identical exception the moment anything on its own request path
  resolves a zone (check before assuming Api was silently fine only by luck rather than by never
  calling the same code path).
- **Every existing non-UTC calendar needs its horizon re-materialized** once this ships — the fix does
  not retroactively backfill; the next scheduled run (or a manual trigger) is what actually produces
  the missing slots. Confirm the test calendar's readiness clears live after deploying, not just that
  the image builds.

## Done when

- [x] `ago-calendar`'s Dockerfile final stage is `10.0-noble-chiseled-extra`.
- [x] A local build of the fixed image, inspected directly, contains `/usr/share/zoneinfo/Europe/Moscow`.
- [x] Deployed live (`ago-calendar#54`); the previously-stuck test calendar materialized 36 slots on
      the worker's own restart with no manual database intervention — readiness now reads "Можно
      записаться", confirmed live in the console.
