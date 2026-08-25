# ADR-0051: a frontend image takes no environment from its build command, and says which commit it is

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 15
- **Extends**: `adr/0047` — same registry, same tag rule, same "no new secret". This adds the four
  frontend images `0047` could not reach, and answers the one question they raise that the three
  .NET hosts do not.

## Context

`adr/0047` moved the three `Ago.Chat.*` hosts to GHCR under their full commit SHA, and made a
running pod able to name the commit it was built from. It could not touch `ago-console`,
`ago-widget` or `ago-landing` — all three had open PRs — and it said so bluntly in its own
Consequences: **the 2026-08-25 incident was a *console* bundle**, so the specific failure that
motivated the whole thing was still possible in the one place it did not reach.

Copying the `ago-chat` publish job into three more repositories is most of the work and none of the
thinking. The thinking is one question those repositories raise and `ago-chat` does not:

**A frontend bundle is configured at build time, not at start time.** `ago-console` reads its API
origin and Keycloak issuer through `import.meta.env`, which Vite resolves while bundling.
`ago-widget`'s demo images took `AGO_API_BASE_URL` as a `docker build --build-arg`, set by
`ago-deploy/k8s/build-static-images.sh`. So before this decision,
`ghcr.io/golyakoff/ago-console:<sha>` did not mean "the console at that commit" — it meant "the
console at that commit, pointed at whichever API the person running `docker build` happened to
name". Two different artifacts, both entitled to the same tag, and the second push wins.

That directly spends what `15-06` bought. A SHA tag that can mean two things is not better than
`:local`; it is worse, because it looks like it means one.

## Decision

### 1. A published frontend image takes no environment input from its build command

Every value that would otherwise vary per environment is a **committed file in the repository**, so
the commit determines the artifact and nothing else does.

| Repository | Where the environment lives now | Change |
|---|---|---|
| `ago-console` | `.env.production`, already committed (`8-02`) | None to the file — but CI's build step used to *override* every `VITE_*` with a localhost placeholder, and process env wins over `.env` files in Vite. Left alone, the publish job would have pushed a console pointed at `localhost` under a tag naming a commit whose `.env.production` says otherwise. The overrides are gone. |
| `ago-widget` | `Dockerfile`'s `ARG AGO_API_BASE_URL=https://chat.reserve-me.ru` | Was passed on the command line by `build-static-images.sh`; now a committed default. `build.mjs`'s refusal to guess an API origin is **untouched** — see below. |
| `ago-landing` | Nothing to configure | None needed. The rule holds here trivially, which is worth noticing rather than skipping: it is what the other two are being made to look like. |

`build-static-images.sh` therefore stopped setting `AGO_API_BASE_URL`, rather than gaining a way to
set it per registry. The point is not to pass the right value; it is for there to be nothing to pass.

**Why the widget's default lives in the `Dockerfile` and not in `build.mjs`.** `build.mjs` is the
*product* build — it produces the bundle a tenant embeds, and it has no deployment, so its guard
("do not invent endpoints", `CLAUDE.md`) is exactly right and stays. The `Dockerfile` is the *demo
packaging*: it exists solely to serve `demo-shop1.reserve-me.ru` and `demo-shop2.reserve-me.ru`, and
it already hardcodes `DEMO_PAGE_DIR=public-demo`, which is precisely as deployment-specific as an API
origin. Naming the origin there keeps the product build honest and makes the image a function of its
commit. `DEMO_PAGE_DIR` remains a command-line argument and is not an exception to the rule: it does
not select an environment, it selects *which of two images is being built* — and that choice is
already in the image's name (`ago-demo-shop1` vs `ago-demo-shop2`), so the tag is not asked to carry it.

### 2. Therefore the environment does **not** go in the tag or the repository name

`15-07` framed two options: accept per-environment images and put the environment in the name, or
move configuration to runtime so one image runs anywhere. This is neither, and it is not a dodge —
it is what makes the first option unnecessary. There is one environment, its values are in git, and
a build cannot deviate from them, so `ago-console:<sha>` already means one thing.

The environment is still knowable from a running pod, transitively and exactly: the commit names the
tree, and the tree contains `.env.production` and the `Dockerfile`'s default. Nothing needs to be
stamped into the artifact that is not already derivable from the commit stamped into it.

**The day this stops being true is the day a second environment exists**, and that is the point to
re-open this decision — with a real staging environment in hand, which `15-07` explicitly puts out of
scope because it does not exist. The runtime-config option (an SPA fetching a small config the
container serves, templated at startup) is the right answer *then*: it is more machinery, and its
whole advantage is one image running in two places, which is worth nothing while there is one place.

The enforceable form of the rule, since a `Dockerfile` `ARG` can always be overridden by hand:
**CI is the only publisher, and CI passes no environment inputs.** An image that reaches the
registry therefore cannot have been pointed anywhere else.

### 3. A running frontend pod names its own commit — from a file, and for the widget also from inside the bundle

`adr/0047` §3 made this true for the hosts by baking the commit into the assembly and serving it at
`GET /healthz/version`. A browser bundle has no process to ask. Two shapes, chosen for two different
reasons rather than for symmetry:

- **`/version.json`, in all four images.** `{"app":"ago-console","commit":"<40 hex>"}` — written by
  the `Dockerfile` from `ARG GIT_COMMIT`, after the content is copied in so nothing can shadow it.
  One shape across four images means `deploy.sh`, `smoke.sh` and a human with `curl` all ask one
  question and parse one answer. It is readable from outside the cluster, which the OCI label is
  not, and without a shell in the container, which `nginx:alpine-slim` barely has.
- **`window.AgoChat.commit`, in the widget bundle only.** The widget is the one artifact that leaves
  an origin we control: a tenant's page fetches `ago-chat.js` and nothing else, so the `version.json`
  sitting beside it in our container is invisible there. The bundle has to carry its own answer, via
  an esbuild `define`. It costs **49 bytes gzipped** (22,546 → 22,595 of a 46,080-byte budget).

Deliberately **no build timestamp** in `version.json`. Two builds of one commit should be the same
artifact, and a clock is the cheapest way to make them differ for no reason at all.

`GIT_COMMIT` defaults to `unknown` rather than failing the build, in every one of the three
Dockerfiles and in `build.mjs`. A local `docker build` to try something is legitimate; it should say
`unknown` out loud rather than refuse, or worse, claim a commit. `smoke.sh` treats `unknown` as a
failure, which is where that distinction is supposed to bite.

### 4. `deploy.sh` moves one frontend at a time

`./deploy.sh <sha>` still means the three hosts, together, because they are three images out of one
repository and one SHA truthfully names all three. `./deploy.sh <console|demo-shop1|demo-shop2|landing> <sha>`
is new. The four frontends come out of **three repositories that move independently**, so a single
tag applied to all four would be a lie about at least two of them — and the same reasoning is why
`overlays/demo`'s `images:` block carries four separate `newTag` values rather than one.
`ago-demo-shop1` and `ago-demo-shop2` do share a tag, because they genuinely are one commit of
`ago-widget` packaged twice.

`rollback.sh` gains the same argument, and `--history` covers all seven. That last change earned
itself immediately: on the live run, `ago-console`'s revisions 1–4 all read `ago-console:local` —
four indistinguishable entries with nothing to go back to — and revision 5 named a commit.

### 5. The four `imagePullPolicy: Never` patches are gone, for `adr/0047` §4's reason

Default `IfNotPresent` on an immutable SHA tag: present in containerd it is used with no network
call, so a node that built its own image behaves as it always did; absent, it is pulled. The live
exercise below confirmed both halves.

## Consequences

- **Every push to `main` in three more repositories permanently publishes images** — four of them.
  Same trade `adr/0018` and `adr/0047` already made, same answer: it is what a release process does.
  Nothing prunes old versions.
- **`ago-landing` gained its first CI workflow.** It had none, which was defensible while nothing
  there was published. Building the image *is* its test — there is no npm project to lint.
- **The four GHCR packages will need their visibility checked once**, exactly as `adr/0047`'s three
  did. A package GitHub creates as private answers an anonymous pull with `403`.
- **Four `imagePullPolicy: Never` declarations are gone; none remain anywhere in `overlays/demo`.**
- **`build-static-images.sh` no longer accepts an API origin.** If someone needs a demo image pointed
  somewhere else, the answer is to change the committed default in a commit — which is the rule
  working, not the rule getting in the way.
- **`smoke.sh` lost two checks and gained nine.** The two it lost sniffed the bundle for a string
  added by a specific past release ("does the CSS carry an `--ago-` token", "does the JS mention
  `configureLogging`"); they could only ever catch drift older than one named change, never drift in
  general. The nine ask each origin what commit it is and compare that to the tag the cluster was
  told to run.
- **A pull failure on a frontend is now possible where it was not**, since `Never` never reached the
  network. It is also now *survivable and visible*, which is the trade: verified live below.

## What was actually performed, on the live deployment

On 2026-08-25, on the real node, with **no change to what any page serves** — every step below moved
identity, not content:

1. All four images built on the node from each repository's currently-deployed commit, with
   `IMAGE_REPO=ghcr.io/golyakoff IMAGE_TAG=commit`, and imported into k3s's containerd. The widget
   bundle came out pointed at `https://chat.reserve-me.ru` **with no build argument passed** — the
   committed `Dockerfile` default doing exactly what §1 claims it does.
2. The four `imagePullPolicy: Never` fields removed from the live Deployments.
3. `./deploy.sh console 6ed0411…` → rolled out, and
   `curl https://console.reserve-me.ru/version.json` answered
   `{"app":"ago-console","commit":"6ed0411ab32166c8d0c41eff75dee87abe61ca28"}`. **This is the thing
   that could not be done on 2026-08-25**, on the exact surface it could not be done for. The served
   `index.html` hashed identically before and after, so the deploy added a name and changed nothing
   else.
4. Smoke at that moment: console green on both new checks, and the other three frontends **red** —
   *"serves no usable /version.json — a pre-15-07 bundle is deployed, and it cannot name its own
   commit"*. A deliberately stale frontend caught by the smoke test rather than by somebody noticing
   the page looks old, which is `15-07`'s last done-when, observed before it was fixed rather than
   argued for afterwards.
5. The other three deployed the same way. 19 passed, 2 failed — both failures correct: the API still
   runs `f3ecc0d…`, which predates `/healthz/version` (`adr/0047` records this), and the widget
   bundle does not yet carry `window.AgoChat.commit`, because it was built from the commit currently
   deployed, which predates this item's own `build.mjs` change. That second one clears itself on
   `ago-widget`'s first `main` build.
6. `./rollback.sh console` → back to `ago-console:local`, still serving `200`, `/version.json` gone.
   `./rollback.sh --history` printed the four indistinguishable `:local` revisions described above.
7. `kubectl set image ago-landing …:0000…0bad` — a deliberately broken deploy, now that `Never` is
   gone and a real pull is attempted. `ImagePullBackOff` on the new pod; the **old pod served `200`
   on every probe** and kept reporting its own commit throughout. `./rollback.sh landing` cleared it.
8. `./deploy.sh console 6ed0411…` returned the console. 18 pods Running, 0 otherwise.

**What this did not do, and could not:** nothing was pulled from GHCR, because no frontend image has
been published yet — the publish jobs land with this item's own merge, so their first execution is
that merge. The images used were built on the node under exactly the names CI will push, which is
the same position `adr/0047` was in on its own day.

**One thing the exercise found that this item did not go looking for.** The node's frontend checkouts
are behind their own `main`: `ago-console` by 2 commits, `ago-widget` by 3. The demo has been serving
stale frontends *again*, quietly, in the same way and for the same reason. It is not fixed here —
deploying newer frontends is a product change with a real chance of needing an API that is not
deployed either — but it is now **visible**, in `overlays/demo/kustomization.yaml`, as four commit
SHAs somebody can compare against `git log`. That visibility is the entire deliverable.

## Alternatives considered

- **Put the environment in the tag or the repository name** (`ago-console:demo-<sha>`,
  `ago-console-demo`). `15-07`'s own first option, and the honest answer *if* the build's inputs
  cannot be pinned down. They can, at a cost of one committed default, so this would have added a
  naming convention to describe a variability that no longer exists — and conventions that describe
  nothing are the ones that rot.
- **Move configuration to runtime** (`config.json` fetched at boot, or templated into the container
  at startup). `15-07`'s second option and the right one for two environments. Rejected for one:
  a config fetch before the app can start, an nginx template step, and a bundle that stops inlining
  the value — all to make one image runnable in a second place that does not exist. Revisit it when
  staging does.
- **A Vite `define` for the console's commit instead of `/version.json`.** Rejected: the console is
  always loaded from an origin that serves `version.json` beside it, so a `define` reaches nothing
  extra, and a file is readable by `curl`, by `smoke.sh` and by the API server's pod proxy without
  parsing a minified bundle. The widget gets the opposite treatment for the opposite reason.
- **Fold the four frontends into `deploy.sh <sha>` with one tag.** Rejected: three repositories, one
  argument, and at least two of the four images would be tagged with a commit they were not built
  from — the precise failure this decision exists to prevent, reintroduced by the tool meant to
  enforce it.
- **A build timestamp in `version.json`.** Rejected: it makes two builds of one commit differ, which
  is the property §1 spends effort to establish.
