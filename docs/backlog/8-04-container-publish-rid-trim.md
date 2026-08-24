# Restrict container publish to linux-x64, trim SkiaSharp's multi-RID runtimes

- **Stage**: 8
- **Status**: done
- **Depends on**: `8-00-minimal-production-base-image.md` — that item's own "Shipped in" note found
  and flagged this as a separate follow-up rather than fixing it in scope; this item is that follow-up.

## Goal

`ago-chat/Dockerfile`'s `dotnet publish` step is RID-restricted to `linux-x64` (framework-dependent,
not self-contained), so the published `/app/runtimes` folder carries only the native assets this
container can actually load, instead of every RID any referenced NuGet package ships assets for.

## Context to read first

`8-00`'s own "Shipped in" note: `Ago.Chat.Worker`'s image stayed at 599MB after the Chiseled switch
because ~440MB of it is `/app/runtimes` — multi-RID SkiaSharp native binaries (win-x64, win-x86,
win-arm64, osx, linux-x64, linux-arm64, linux-musl-*, ...), because the `dotnet publish` in
`ago-chat/Dockerfile`'s build stage carries no `-r`/`--self-contained` restriction, so NuGet resolves
and ships the package's full cross-platform `runtimes/` folder. `src/Ago.Chat.Worker/
Ago.Chat.Worker.csproj` references SkiaSharp for attachment thumbnail generation (`5-04`). The build
stage's own base image (`mcr.microsoft.com/dotnet/sdk:10.0`) and the final stage's
(`...-noble-chiseled`) are always Linux, and the compose/k3s targets are always `linux-x64` — there is
no scenario where this Dockerfile needs to produce a build for any other RID.

## Scope

- Add `-r linux-x64 --self-contained false` to the `dotnet publish` (and the preceding `dotnet
  restore`, so the RID-specific assets are already fetched by the time publish runs) in
  `ago-chat/Dockerfile`'s build stage. Framework-dependent stays framework-dependent — only the RID
  is pinned, not the deployment mode — so the final stage's ASP.NET base image still supplies the
  shared runtime.
- Rebuild and smoke-test **all three** hosts (`Api`, `Worker`, `Webhooks`) even though only `Worker`
  references SkiaSharp — all three build from the one shared Dockerfile and the one changed publish
  line.
- Measure real image sizes before/after with `docker image ls` — do not assume the reduction, report
  the number.
- Update `docs/runbooks/local-dev.md` if the measured sizes or the documented build command change.

## Out of scope

- Any other native-asset dependency or packaging concern — this item is the RID restriction alone.
- Re-opening `8-00`'s base-image or entrypoint decisions.

## Done when

- [x] `ago-chat/Dockerfile`'s build stage publishes with `-r linux-x64 --self-contained false`.
- [x] All three hosts build and were run for real against the compose loop (or an equivalent real
      check) — not asserted.
- [x] `/app/runtimes` under `Ago.Chat.Worker`'s published output carries only `linux-x64`'s SkiaSharp
      assets, not every RID.
- [x] Before/after image sizes are reported as real numbers for all three hosts.
- [x] `docs/runbooks/local-dev.md` updated with the new numbers.

## Open questions

None.

## Shipped in

`ago-chat`: `Dockerfile`'s build-stage `dotnet restore`/`dotnet publish` both pinned to `-r linux-x64`,
publish additionally given `--self-contained false` (framework-dependent unchanged, only the RID
narrowed). All three hosts rebuilt and smoke-tested against the compose loop.

**Real image-size numbers** (`docker image ls`, before vs. after this change, same base as `8-00`):
Api 140MB -> 140MB, Webhooks 139MB -> 139MB (neither references a multi-RID native package, so no
change), Worker 599MB -> 151MB (~75% smaller, ~448MB removed). Confirmed directly (`docker cp` out of
a non-started container): the "before" Worker image's `/app/runtimes` held 17 RID folders
(`linux-x64`, `linux-arm64`, `linux-musl-*`, `win-x64`, `win-arm64`, `osx`, ...); the "after" image has
no `/app/runtimes` directory at all - the RID-specific publish places `libSkiaSharp.so` directly under
`/app`.

**Verified live against the compose loop**, all three hosts run with the same env-var wiring
`ago-deploy/k8s/base/*.yaml` uses (Postgres/RabbitMQ/Redis/MinIO/Keycloak service hostnames):
`/healthz/live` and `/healthz/ready` both 200 on Api, Worker, and Webhooks; a real
`POST /api/v1/visitor-sessions` against the RID-restricted Api image returned `201` with a real JWT
and visitor id against the seeded demo site. Same harmless `Cannot load library libgssapi_krb5.so.2`
warning as `8-00` (Npgsql's optional GSSAPI probe), nothing new.

`docs/runbooks/local-dev.md` updated with the measured sizes and the runtimes-folder finding.
