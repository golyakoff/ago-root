# The frontends never joined the registry

- **Stage**: 15
- **Status**: ready
- **Depends on**: `15-06-image-registry-and-deploy-rollback.md` (shipped) — this is the half of it that
  was not done, and the shape to copy already exists

## Goal

Every image the demo runs is identifiable by the commit it came from, not just the three
`Ago.Chat.*` hosts. Today `ago-console`, `ago-widget`'s two demo pages and `ago-landing` are still
built on the node under the mutable tag `:local`, and nothing about a running pod says which commit is
inside it.

## Why this matters more than it sounds

`15-06` exists because of one incident: on 2026-08-25 the public console served a bundle a week stale,
and there was no way to tell from the outside or from the cluster. **That incident was the console** —
and the console is exactly what this item covers and `15-06` did not. The half that was fixed is the
half that had not caused the problem.

Not necessarily an oversight — narrowing an item to one repository is a reasonable way to keep it
shippable. But `15-06` now reads as closed while the surface that motivated it still behaves the old
way, and that gap should be written down rather than inferred later from a second identical incident.

## What already exists to copy

- `ago-chat`'s CI has a `publish-images` job: `permissions: packages: write`, `docker login ghcr.io`
  with the built-in `GITHUB_TOKEN` (**no new secret** — the same mechanism `ago-platform` publishes
  packages with), pushing `ghcr.io/golyakoff/ago-chat-*:<commit-sha>`.
- `build-images.sh` takes `IMAGE_REPO`/`IMAGE_TAG` so a node-side build produces exactly the names CI
  would have pushed.
- `overlays/demo/kustomization.yaml`'s `images:` block pins the three tags, and `smoke.sh` compares
  what is running against what is pinned.

`build-static-images.sh` has **none** of that: it hardcodes `:local` and knows nothing about a
registry.

## The real design question, which is not a copy of `ago-chat`

**The frontend images are environment-specific by construction.** `ago-console` reads its API address
from `VITE_API_BASE_URL` through `import.meta.env`, which Vite resolves *at build time*; the widget
demo images take `AGO_API_BASE_URL` (and `DEMO_PAGE_DIR`) as build args. So
`ghcr.io/…/ago-console:<sha>` is not "the console at that commit" — it is "the console at that commit,
pointed at whichever API host built it."

That collides with what `15-06` bought: a tag that means one thing. Two honest answers, and the item
picks one:

- **Accept it**, and make the tag say so — the environment belongs in the tag or the repository name,
  and the manifests and `deploy.sh` learn that frontends are pinned per environment. Smaller change,
  and it keeps a build-time-configured SPA, which is the simplest thing that works.
- **Move the address to runtime**: the SPA reads a small config the container serves, so one image runs
  anywhere and the tag means what it means for `ago-chat`. More machinery — a config file mounted or
  templated at startup, and a build that stops inlining the value — and it is the answer that scales
  when there is a staging environment, which today there is not.

Neither is obviously right at this size. What is not acceptable is publishing a per-environment image
under a tag that pretends otherwise.

## Scope

- A `publish-images` job in each of `ago-console`, `ago-widget` and `ago-landing`, modelled on
  `ago-chat`'s — built-in token, no new secret.
- `build-static-images.sh` gains `IMAGE_REPO`/`IMAGE_TAG`, so a node-side build produces the same names,
  exactly as `build-images.sh` already does.
- The environment question above decided, recorded, and reflected in how the images are named.
- `overlays/demo`'s `images:` block extended to the frontend images, and its `imagePullPolicy: Never`
  patches removed for the same reason `15-06` removed the others.
- `deploy.sh` and `rollback.sh` cover the frontends, or state plainly that they do not and why.
- `smoke.sh`'s bundle checks compare against the pinned tag rather than only asserting the CSS is not
  the old stub.

## Out of scope

- A staging environment. It is the strongest argument for the runtime-config option and it does not
  exist; if it ever does, that decision gets revisited with a real second environment in hand.
- Changing how the widget is delivered to a tenant's page (`edge.md`'s CDN note).
- Anything about the `Ago.Chat.*` hosts — `15-06` did those.

## Done when

- [ ] All four frontend images are published by CI under a commit-identifiable tag.
- [ ] `build-static-images.sh` can produce the same names on the node.
- [ ] The environment question has a recorded answer and the naming reflects it.
- [ ] `deploy.sh --current` shows the frontends too, or says why not.
- [ ] A deliberately stale frontend is caught by `smoke.sh` rather than by somebody noticing the page
      looks old.

## Open questions

None. The environment decision is this item's own to make and record.
