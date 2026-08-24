# Switch Ago.Chat.* hosts to a minimal production base image

- **Stage**: 8
- **Status**: ready
- **Depends on**: nothing — pure Dockerfile/build change, no relation to `8-01`'s hosting/domain
  decision (both now resolved: k3s VPS, `*.ago.golyakov.net`), verified only against the local
  compose loop, not the public deployment

## Goal

Every `Ago.Chat.*` host (`Api`, `Worker`, `Webhooks`) ships from a minimal production base image
instead of the full `mcr.microsoft.com/dotnet/aspnet:10.0` (Debian) image every host currently uses,
before any of it reaches a public VPS. Smaller attack surface and image size matter more once the
target is a small, real k3s VPS than they did for a local Docker-Desktop cluster with no exposure.

## Context to read first

`docs/backlog/8-01-public-deployment-target.md`'s own "Note added 2026-08-25" — the research already
done: **Ubuntu Chiseled** (`mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled`) is current .NET
guidance's default recommendation for production with no special requirements (smaller than Alpine
in practice, no shell/package manager, glibc-based so it sidesteps Alpine's own musl-compatibility
risk for native dependencies). **Alpine** (`...-alpine`) is the named fallback if Chiseled's own
missing shell breaks something this project's Dockerfile/entrypoint needs, or a native dependency
turns out not to be musl-clean. `docs/conventions/date-and-time.md` — this project's UTC-only,
`DateTimeOffset`-everywhere convention, relevant to whether Chiseled's default ICU-less variant (no
globalization support) is actually a problem here or not.

`ago-chat/Dockerfile` (single shared file, all three hosts, selected via `--build-arg
PROJECT_NAME=...`) — its own final-stage `ENTRYPOINT ["sh", "-c", "exec dotnet \"$PROJECT_DLL\""]`
uses a shell to expand the `PROJECT_DLL` env var. **Chiseled images ship with no shell at all** — this
entrypoint as written will not run on a plain Chiseled final stage. This is exactly the risk the
8-01 note flagged as needing verification against the real image, not assumed either way — and now
confirmed as a real, concrete blocker to resolve, not a hypothetical one.

## Scope

- Fix the shell-dependent entrypoint so it works without a shell in the final stage: bake the
  concrete DLL name into a fixed filename during the `build` stage (which still has a full SDK image
  with a shell available) — e.g. copy/rename the published output to a fixed name there — so the
  final stage's `ENTRYPOINT` can be a literal JSON-array exec form (`["dotnet", "<fixed-name>.dll"]`)
  needing no runtime shell expansion at all. Do not carry the `sh -c` wrapper into the final stage
  under Chiseled.
- Switch the final stage to `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled` per the note's own
  default recommendation. Decide the ICU question for real rather than assuming: this project's
  `DateTimeOffset`-only convention suggests the non-`-extra` (no globalization) variant is fine, but
  confirm nothing in the actual dependency closure (Npgsql, StackExchange.Redis, RabbitMQ.Client,
  ASP.NET's own model binding/validation) throws on startup or on a real request without ICU before
  deciding the leaner variant is correct - if it does, use `-extra` and say why in this item's own
  Shipped-in note, don't silently swap without explanation.
- If Chiseled turns out to break something real (a native dependency, not just the shell issue
  already found and fixed above) that isn't worth working around, fall back to Alpine per the note's
  own named contingency, and say plainly why Chiseled didn't work out - don't silently prefer Alpine
  without first giving Chiseled a real, verified attempt.
- Verify for real, not just "it builds": build all three host images
  (`--build-arg PROJECT_NAME=Ago.Chat.Api|Worker|Webhooks`), run each against the existing compose
  loop's own Postgres/Redis/RabbitMQ/Keycloak/MinIO, and confirm each host actually starts and serves
  a real request - `Api`'s `/healthz/live` returns 200 at minimum; if practical within this item's own
  scope, a real visitor-session create or a Worker/Webhooks smoke matching whatever `local-dev.md`
  already documents as the fastest real check for each host.
- Update `docs/runbooks/local-dev.md`/`k8s-local.md` if the image switch changes anything a reader
  would need to know (build command, image size worth noting, a startup-time difference).

## Out of scope

- Anything about the actual public VPS deployment, DNS, or TLS - that is `8-01`'s own job, now
  unblocked (k3s VPS, `*.ago.golyakov.net` subdomains) but not started by this item.
- `ago-platform`/`ago-console`/`ago-widget`'s own build/deploy shape - this item is `ago-chat`'s three
  hosts only, the ones the note was attached to.
- Re-architecting the shared single-Dockerfile-with-build-arg approach itself - only the final stage's
  base image and entrypoint shape change, not the overall structure the file's own header comment
  already explains and justifies.

## Done when

- [ ] `ago-chat/Dockerfile`'s final stage uses `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled`
      (or, if genuinely necessary and stated why, the Alpine fallback) instead of the full `aspnet:10.0`
      image, with an entrypoint that does not depend on a shell existing in the final stage.
- [ ] All three hosts (`Api`, `Worker`, `Webhooks`) build successfully from the changed Dockerfile and
      were run for real against the compose loop's own dependencies - not asserted, actually started
      and actually served/processed a real request each.
- [ ] The ICU/globalization decision (leaner non-`-extra` vs. `-extra`) is stated and justified against
      this project's own real dependency closure, not assumed from the note's own general reasoning
      alone.
- [ ] Image size before/after is reported as a real number (`docker image ls`), not asserted as
      "smaller" without a measurement.
- [ ] Any runbook that documents the build/run commands is updated if the switch changed them.

## Open questions

None - `8-01`'s own note already resolved the base-image research question; this item is that research
applied and verified against the real Dockerfile and the real dependency closure.
