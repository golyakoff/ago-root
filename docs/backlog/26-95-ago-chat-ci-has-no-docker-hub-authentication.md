# 26-95 · `ago-chat`'s CI has no Docker Hub authentication, and Testcontainers hit its rate limit live

- **Stage**: 26
- **Status**: ready — the fix needs the author's own call on where the credential comes from
- **Found**: 2026-09-24, landing `26-82` — `Ago.Chat.Integration.Tests` hung for 30+ minutes on GitHub's
  hosted runner, twice on the identical commit, with no code change between the two runs.

## What is actually true today, confirmed against the real, cancelled run's own log

`ago-chat`'s CI (`.github/workflows/ci.yml:120-123`) logs into `ghcr.io` with the workflow's own token,
for pulling this project's own published images — and logs into nothing else. Every Testcontainers
fixture in `Ago.Chat.Integration.Tests` pulls `postgres`/`rabbitmq` (and whatever else) from Docker Hub
**anonymously**. Docker Hub rate-limits anonymous pulls per source IP, and GitHub-hosted runners share a
small, heavily-reused IP range across every repository on the platform — a well-known, common failure
mode for exactly this combination.

The real, cancelled run's own log names it directly, on a test this item's own change never touched:

```
Ago.Chat.Integration.Tests.AttachmentThumbnailEndToEndTests.ConfirmingAnImageAttachment_ProducesARealThumbnail_ViaTheRealOutboxAndConsumer [FAIL]
Docker.DotNet.DockerApiException : Docker API responded with status code='InternalServerError',
response='{"message":"unauthorized: access to the requested resource is not authorized"}'
  at DotNet.Testcontainers.Clients.DockerImageOperations.CreateAsync(...)
  at DotNet.Testcontainers.Clients.TestcontainersClient.PullImageAsync(...)
```

Five of the six other test assemblies (`Domain`/`Application`/`FakeCrm`/`Architecture`/`Concurrency`)
finished in the first ~2.5 minutes, exactly matching a real, healthy local run's own timing. Only
`Integration.Tests` — the one assembly whose fixtures pull container images — then ran for another 30+
minutes before being cancelled, evidently retrying failed pulls across many container-backed tests
rather than failing fast. This happened on two separate re-runs of the identical commit, ruling out a
one-off network blip.

## Scope

One promise: **Testcontainers in CI pulls its images authenticated, not anonymously.**

- `docker/login-action` (or the equivalent plain `docker login docker.io`, matching this file's own
  `ghcr.io` step's style) added to the `build-test` job, before the `Test` step, using a Docker Hub
  username + access token.
- **The credential itself is the author's own call, not this item's** — a personal Docker Hub account's
  token, an organization one, or (simplest, if acceptable) Docker's own free "Docker Hub" service
  account flow. Whichever it is, it is a new secret (`docs/architecture/secrets.md` gains a row) and
  needs to be added to the repository's own Actions secrets before this can be wired up — a step the
  managing session cannot take on its own.
- Alternative worth naming rather than silently preferring: mirroring the specific images this project
  actually pulls (`postgres`, `rabbitmq`, whatever else `Testcontainers` fixtures name) into `ghcr.io`,
  which is already authenticated — trades a new secret for a new, manually-kept-in-sync mirror. Login is
  simpler and is what this item assumes unless the author prefers otherwise.

## Out of scope

- Any change to the tests themselves, or to `Ago.Chat.Integration.Tests`' own fixtures — nothing here is
  a code defect.
- `ago-calendar`/`ago-platform`'s own CI, if either also runs Testcontainers-backed integration tests
  unauthenticated — check and file separately if so; not verified as part of this item.

## Done when

- [ ] A Docker Hub credential exists in the repository's Actions secrets, and `docs/architecture/secrets.md`
      names it, who holds it, and what rotating it costs — the same bar every other row in that file
      already meets.
- [ ] CI logs into Docker Hub before the `Test` step.
- [ ] A real CI run's own log shows an authenticated pull (not the anonymous rate-limit error above) for
      at least one Testcontainers fixture.
- [ ] `Ago.Chat.Integration.Tests` completes in CI within the same rough window a healthy local run
      already takes (single-digit minutes), not 30+.
