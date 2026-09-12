# `minio/minio` no longer exists on Docker Hub

- **Stage**: 15
- **Status**: ready
- **Verified**: 2026-09-12 — confirmed live: `https://hub.docker.com/v2/repositories/minio/minio/`
  returns `{"message":"object not found"}`; the exact pinned tag this project uses,
  `RELEASE.2025-09-07T16-13-09Z`, resolves cleanly on `quay.io/minio/minio` (`200 OK`, real
  `Docker-Content-Digest`) via an anonymous pull token — see Context below for how this was found.
- **Depends on**: nothing
- **Found**: 2026-09-12, `ago-chat#258`'s CI run failed five `Ago.Chat.Integration.Tests.Erasure*`
  tests with `Docker.DotNet.DockerApiException: pull access denied for minio/minio ... denied` — not
  a code regression in that PR's own change, a registry-side removal.

## Goal

Every place this project pins `minio/minio:<tag>` instead resolves to an image that still exists,
so CI stops failing on every PR that happens to spin up the MinIO testcontainer fixture, and the
live deployment's own MinIO pod can still be pulled fresh on a node replacement or a scale event.

## Context to read first

MinIO stopped publishing to Docker Hub under the `minio/minio` name; their own current guidance
points at `quay.io/minio/minio`, which mirrors every tag Docker Hub used to carry, including this
project's own pinned `RELEASE.2025-09-07T16-13-09Z` (confirmed above). This is a registry-address
change only — nothing about the image's own content, entrypoint, or tag scheme changes.

## Where it is pinned

- `ago-chat/tests/Ago.Chat.Integration.Tests/AttachmentFixture.cs`
- `ago-chat/tests/Ago.Chat.Integration.Tests/AttachmentThumbnailEndToEndTests.cs`
- `ago-chat/tests/Ago.Chat.Integration.Tests/ErasureFixture.cs`
- `ago-deploy/docker/docker-compose.yml`
- `ago-deploy/k8s/backup/docker-compose.restore-drill.yml`
- `ago-deploy/k8s/base/minio.yaml` (two references — an init step and the container itself)

All six currently read `minio/minio:RELEASE.2025-09-07T16-13-09Z`; all six become
`quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z`. No other change.

## Scope

- Repoint every reference above at `quay.io/minio/minio`, same tag.
- Confirm `ago-chat`'s integration suite is green again with the new address (this is the
  fails-before/passes-after here: the five `Erasure*` tests fail against the old address for a
  registry reason, not a code reason, and pass once repointed).
- The live deployment's running MinIO pod is not itself broken right now (nothing has restarted it
  since the old image was already pulled and cached, and no `imagePullPolicy` is set so Kubernetes
  defaults to `IfNotPresent` on a tagged image) — but the manifest fix should land and be deployed so
  the next redeploy or node event does not hit this cold.

## Out of scope

- Any other Docker Hub image this project pins — this item is scoped to the one repository that was
  actually observed to disappear. A general "audit every pinned image for registry survival" sweep is
  a different, open-ended item if it's ever wanted.
- Pinning by digest instead of tag — a real hardening step, not what broke here.

## Done when

- [ ] All six references read `quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z`.
- [ ] `ago-chat`'s full test suite is green, including `Ago.Chat.Integration.Tests`.
- [ ] The `ago-deploy` change is deployed to the live stand (manifest applied, not just committed).
