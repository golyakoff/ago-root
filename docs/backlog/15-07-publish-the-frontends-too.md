# The frontends never joined the registry

- **Stage**: 15
- **Status**: done (2026-08-25) — `adr/0051`; **one author step remains, named at the bottom**
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

### The answer: neither, because the premise can be removed — `adr/0051`

The image is only environment-specific because a **build-command argument** made it so. Take that
away and it stops being one.

- `ago-console`'s values already live in a **committed** `.env.production`, so they are a property of
  the commit, not of whoever ran `docker build`. (The one real bug here was on the other side: CI's
  build step overrode every `VITE_*` with a localhost placeholder, and process env beats `.env` files
  in Vite — so the publish job would have pushed a localhost console under a truthful-looking SHA.
  Those overrides are gone; CI now builds exactly what ships.)
- `ago-widget`'s `AGO_API_BASE_URL` became a committed default in the **`Dockerfile`**, not in
  `build.mjs`. `build.mjs` is the *product* build and its refusal to invent an endpoint stands
  untouched; the `Dockerfile` is the *demo packaging*, and it already hardcodes which demo page goes
  in, which is exactly as deployment-specific.
- `ago-landing` has no configuration at all.

So the environment goes **neither in the tag nor into a runtime fetch**: `ago-console:<sha>` is a
function of the commit, and the environment is knowable from the commit because it is in the tree the
commit names. `build-static-images.sh` therefore *lost* its `AGO_API_BASE_URL` rather than gaining a
registry-aware version of it — the goal is not to pass the right value, it is that there is nothing
to pass. The enforceable form, since an `ARG` can always be overridden by hand: **CI is the only
publisher, and CI passes no environment inputs.**

This is the first option's outcome without the first option's naming convention. The second option is
right the day a second environment exists, which is the day to re-open it — and that is out of scope
here precisely because it does not.

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

- [x] All four frontend images are published by CI under a commit-identifiable tag. A
      `publish-images` job in each of `ago-console`, `ago-widget` (two images) and `ago-landing`,
      `main`-only, after the build job passes, `ghcr.io/golyakoff/…:<40-char SHA>` plus a moving
      `main`, no new secret. **Not yet observed running** — the jobs land with this item's own merge,
      so their first execution is that merge.
- [x] `build-static-images.sh` can produce the same names on the node. `IMAGE_REPO` +
      `IMAGE_TAG=commit`; used exactly that way in the live exercise below. `commit` means *each
      image takes its own repository's HEAD*, which is this script's one real difference from
      `build-images.sh` — four images out of three repositories cannot share one honest tag.
- [x] The environment question has a recorded answer and the naming reflects it. `adr/0051`: the
      build takes no environment input, so the name needs to carry none. Section above.
- [x] `deploy.sh --current` shows the frontends too — a seven-row table, tag beside reported commit,
      read from `/version.json` over the API server's pod proxy. `deploy.sh <frontend> <sha>` and
      `rollback.sh <frontend> [<sha>]` are new; `rollback.sh --history` covers all seven.
- [x] A deliberately stale frontend is caught by `smoke.sh` rather than by somebody noticing the page
      looks old. **Observed live before it was fixed**, not argued for afterwards: with only the
      console migrated, smoke read *"demo-shop1.reserve-me.ru serves no usable /version.json — a
      pre-15-07 bundle is deployed, and it cannot name its own commit"* for the other three.

## What was verified live

`adr/0051`'s "What was actually performed" has the sequence. In short, on the real node on
2026-08-25, with **no change to what any page serves** (the served `index.html`, `ago-chat.js` and
apex page hashed identically before and after — the deploys moved identity, not content):

- all four images built on the node under the exact names CI will push, and imported into containerd;
  the widget bundle came out pointed at the real API **with no build argument passed**, which is
  `adr/0051` §1 working rather than being asserted;
- the four `imagePullPolicy: Never` fields removed from the live Deployments;
- `./deploy.sh console <sha>` → `curl https://console.reserve-me.ru/version.json` answered with the
  commit. **That is the thing nobody could do on 2026-08-25, on the exact surface they could not do
  it for**;
- `./rollback.sh console` → back one revision, still serving; `--history` showed four
  indistinguishable `ago-console:local` revisions and one that names a commit;
- a deliberately broken landing deploy → `ImagePullBackOff` while the old pod served `200` throughout
  and kept reporting its own commit;
- final smoke: 19 passed, 2 failed, both correct — the API predates `/healthz/version` (`adr/0047`
  records this), and the widget bundle predates `window.AgoChat.commit` because it was built from the
  commit currently deployed. The second clears itself on `ago-widget`'s first `main` build.

## What this item found that it was not looking for

**The node's frontend checkouts are behind their own `main` right now** — `ago-console` by 2 commits,
`ago-widget` by 3. The demo has been serving stale frontends again, quietly, in the same way and for
the same reason as on 2026-08-25. Deliberately **not** fixed here: deploying newer frontends is a
product change, and `ago-widget`'s `main` carries `17-07`'s renewal path whose server side (`17-08`)
may not be deployed. It is now *visible* instead — `overlays/demo/kustomization.yaml` pins four
commit SHAs anybody can compare against `git log`, which is the whole deliverable.

## Open questions

None about the decision itself. One thing needs the author, once, and it is the same step `15-06`
left behind:

**After each repository's first publish to `main`, check that the four container packages are
public** — `ago-console`, `ago-demo-shop1`, `ago-demo-shop2`, `ago-landing`. GitHub may create a new
container package as private even when a public repository's own workflow published it, and while one
is private the node's anonymous pull gets `403 Forbidden`. Flipping each to public in its package
settings is the whole fix. Leaving them private works too, at the cost of a `read:packages` PAT held
as an `imagePullSecret` — a second credential `adr/0047` chose GHCR partly to avoid.

And then, once: update the four `newTag` values in `overlays/demo/kustomization.yaml` to the commits
CI actually published, and `./deploy.sh <frontend> <sha>` each. Until that happens, those four tags
name node-built images that exist only in this node's containerd — stated in the file itself.
