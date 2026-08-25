# ADR-0047: images go to GHCR under a commit-SHA tag, and a rollback is a first-class operation

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 15
- **Amends**: `adr/0026` (its "Image delivery" section only — every other decision in that ADR stands)
- **Extended by**: `adr/0051` (`15-07`) — the four static bundles this ADR could not reach. Its
  Consequences below said the 2026-08-25 failure was still possible in the one place this decision
  did not touch; `0051` is that place, and it is closed.

## Context

`adr/0026` chose to build container images directly on the VPS and import them into k3s's own
containerd (`k3s ctr images import`), with `imagePullPolicy: Never` patched onto the three
`ago-chat-*` Deployments. The reasoning was sound for what it was solving: a registry meant a new
dependency and a second GitHub token beside the `read:packages` one `adr/0018` had just introduced,
and `8-01` had explicitly scoped CI/CD out.

Two costs turned real on **2026-08-25**, both inside one day:

- **A console bundle a week stale.** `ago-console`'s checkout on the node was six commits behind and
  had been serving a pre-`11-05` bundle for a day. Nothing reported it, because nothing could.
- **No way to tell.** Every image wore the tag `:local`. A running pod could not name the commit it
  came from, and neither could the Deployment that scheduled it. The only record of "what is
  deployed" was the state of a working directory on one machine.

`redeploy.sh` was written the same day and fixed the first half: the sequence is now a script rather
than a list somebody reads selectively. It could not fix the second half, and its own closing section
says so — **a procedure can be made repeatable; only an artifact can be made identifiable.**

Two other things depend on this being resolved:

- **`15-02`'s restore drill.** A rebuilt cluster has nothing to run. Build-on-node makes bring-up
  depend on the node having a .NET SDK, Docker, Buildx and enough RAM to compile — which is exactly
  the state a restore drill cannot assume.
- **`17-04`'s image scanning.** Scanning is meaningless until images are published somewhere a
  scanner can reach.

And there is no earlier artifact anywhere. Rolling back meant checking out an earlier commit and
rebuilding it — which is not a rollback, it is a re-derivation, and it takes as long as the outage.

## Decision

### 1. The registry is GHCR (`ghcr.io`), packages public

`ghcr.io/golyakoff/ago-chat-api`, `-worker`, `-webhooks`. Pushed by `ago-chat`'s own CI, on `main`
only, after `build-test` passes.

The options, with what each actually costs and where each stores the bytes:

| | Cost | Where the bytes live | New credential | New account |
|---|---|---|---|---|
| **GHCR (chosen)** | Free for **public** packages — GitHub's published terms place no storage or transfer charge on them. Private packages consume the Free plan's package quota (500 MB storage, 1 GB/month egress), which ~200 MB × 3 images exhausts in two builds. | GitHub (Microsoft), US | **None to publish** — a repository's own `GITHUB_TOKEN` with `packages: write` writes to its own feed. None to pull either, while the packages are public. | No — `adr/0018` already publishes NuGet here |
| Docker Hub | Free for public repositories, but anonymous pulls are rate-limited per source IP (published limit: 100 per 6 hours; 200 for a free authenticated account). A single node pulling three images occasionally will not hit it — the objection is that the limit is externally controlled and has been revised more than once, so it is a failure mode owned by someone else. | Docker Inc., US | A Docker Hub access token, held as a CI secret | **Yes** |
| A registry on the node (`registry:2`, or a k3s-side mirror) | ~100–200 MB of RAM and disk on a node `adr/0026`'s own sizing math leaves ≈1.75–2.35 GiB of headroom on, **plus** TLS and authentication before CI could push to it at all — without which it is a slower `ctr images import` with extra parts. | The node — Russia | Registry auth, generated and held by us | No |
| A Russian cloud registry (Yandex Container Registry, VK, Selectel) | Real money: per-GB-month storage plus egress. Small for ~600 MB of images — but it adds a billing relationship and a service-account key that must live in the cluster as a Secret. | Russia | A service-account key, as an `imagePullSecret` | **Yes** |

**Why GHCR and not the node.** The author has twice chosen self-hosted over a third party — `adr/0040`
for outbound mail, and again for inbound. That instinct is not being ignored here; it is being
checked against what it was actually protecting. Both mail decisions were about **customer data and
sending reputation**: things that are ours, that leak, and that a vendor can damage. A container
image is the compiled output of a **public** repository. It carries no personal data
(`personal-data.md` already records this exclusion explicitly), and nothing about it is confidential.
The property that decided the mail question is absent here, so the conclusion does not transfer.

**What does decide it** is the failure this item exists to fix. A registry on the node cannot serve
the case that motivates having one: `15-02`'s rebuilt cluster, where the node is what was lost. Nor
does it survive the node. It would give us a registry that works in exactly the situations we do not
need one.

**Why not a Russian cloud registry.** `personal-data.md` establishes the residency default — "the
default answer for any new destination is *in Russia*" — and then names its own boundary in the same
breath: **"the rule binds destinations, not images"**, with `15-06`'s registry called out by number as
out of scope. This ADR is that exclusion being used, not routed around.

**Why not Docker Hub.** It buys nothing GHCR does not, and costs an account and a credential.

### 2. The tag is the full 40-character commit SHA

`ghcr.io/golyakoff/ago-chat-api:f3ecc0d87bb20d3de467a1aeeb5c4d636bc48a65`.

Not `sha-f3ecc0d`, not a build number, not a semantic version. The full SHA is what `git rev-parse
HEAD` prints, so "which commit is this?" is a string comparison with nothing to decode and no lookup
table in between.

CI also pushes a moving `main` tag, for the convenience of "whatever is newest". **`deploy.sh`
refuses it**, along with anything else that is not 40 hex characters — a tag that names a moment
rather than a build cannot be rolled back to, and refusing it at deploy time is cheaper than
discovering it during an incident. There is deliberately **no `latest` at all**: not published, so it
cannot be reached for.

### 3. A running pod names its own commit, from inside the binary

The tag is a label somebody chose, and somebody can choose it again — a re-pushed tag, an edited
manifest, a hand-run `kubectl set image`. So the commit is also carried where nothing outside the
build can touch it:

- The Dockerfile passes `-p:SourceRevisionId=$GIT_COMMIT` to `dotnet publish`. The SDK appends
  `+<sha>` to `AssemblyInformationalVersion`, so the commit is compiled into the assembly.
- Every host serves it at **`GET /healthz/version`** →
  `{"host":"Ago.Chat.Api","version":"1.0.0","commit":"f3ecc0d…"}` (`BuildInfoResponse`,
  `Ago.Chat.Contracts`). Unauthenticated, next to the health checks: the commit of a public
  repository is not a secret, and a version check that needs a token is a version check nobody runs.
- The final image also carries OCI annotations — `org.opencontainers.image.revision` and `.source` —
  for tooling that cannot run the container. `.source` is not decoration: GHCR uses it to link the
  published package back to its repository.

`deploy.sh --current` prints the tag and the reported commit **side by side, in two columns**. They
agree until someone makes them disagree, and the day they disagree is the day the pairing earns its
place. `smoke.sh` fails if the API reports no commit, reports `unknown`, or reports one that does not
match its own image tag.

Three hosts deploy from one commit, so a disagreement *between* them is a half-finished deploy —
which is why `/healthz/version` reports the host name too, and why the check looks at all three.

### 4. The demo overlay pulls; `imagePullPolicy: Never` is gone

The three patches are removed. The default for a non-`:latest` tag is `IfNotPresent`, which is
exactly right for an immutable SHA tag: present in containerd it is used with no network call — so a
node that built or imported its own image behaves as it always did — and absent, it is pulled. `Never`
cannot do the second half, and the second half is what lets a rebuilt cluster start at all.

The Keycloak patch's comment, which existed to explain why *it* had no `Never` patch, is rewritten
rather than deleted. The rule it was an exception to no longer exists; the bug it records —
`ErrImageNeverPull` on 2026-08-24, from a patch copied because its neighbours had one — is worth
keeping.

`k8s/overlays/demo/kustomization.yaml`'s `images:` block is **the record of what this environment is
meant to be running**, in git, reviewable. `deploy.sh` uses `kubectl set image` and does not edit it,
so a `kubectl apply -k` resets the cluster to the tag committed there. That is a trap unless it is
stated, so it is stated — in the file, in `deploy.sh`'s own output, and in `redeploy.md`.

`overlays/local` is untouched. On Docker Desktop the cluster and the source tree are the same
machine, a mutable tag costs nothing, and `:local` + `Never` remains the right answer there.

### 5. Rollback is a script, and it has been run

`k8s/rollback.sh`, separate from `deploy.sh` on purpose: during an incident the thing you want is one
word with no arguments to get wrong.

- `./rollback.sh` — `kubectl rollout undo` on all three hosts. It uses the Deployment's own revision
  history, which is stored in the cluster and does not depend on the registry — so it still works
  when the reason for the rollback *is* that the registry is unreachable. That is why it is the
  no-argument path.
- `./rollback.sh <sha>` — delegates to `deploy.sh`. Rolling back to a named build is the same
  operation as rolling forward to one; only the intent differs, and intent is not a code path.
- `./rollback.sh --history` — what each stored revision would restore, by image, which
  `kubectl rollout history` does not show.

### 6. Migrations versus rollback — the asymmetry, written down

**Rolling an image back does nothing at all to the database.** Neither script touches the schema, and
that is deliberate rather than missing.

It is survivable only because every migration in this project so far has been **additive**: code from
an earlier commit runs unharmed against a later schema, ignoring columns it does not know about. That
is a property to keep on purpose, not a run of luck. The rule this ADR adopts:

> A migration must remain compatible with the image immediately before it. Expand now, contract in a
> later release.

A destructive change — dropping or renaming a column, narrowing a type — **breaks rollback outright**.
If one is ever merged, recovery from a bad deploy stops being "roll the image back" and becomes
"restore from backup" (`15-02`). That has to be said in *that* migration's own review, before it
merges, because afterwards is too late to find out.

The inverse direction is the ordinary one and `redeploy.sh` already gets it right: migrations run
**before** the restart, so the old code is briefly running against the new schema — which additive
migrations make safe — rather than the new code against the old schema, which is the failure that
started all of this.

## Consequences

- **One step needs the author, once.** GitHub may create a new container package as private even when
  published by a public repository's own workflow. While it is private, the node's anonymous pull
  gets `403 Forbidden` — observed live during this item's rollback exercise, against a package that
  did not exist yet, which produces the same symptom. After CI's first publish, check the package's
  visibility and set it to public if it is not. Nothing else changes if it is public; if it is left
  private, every pull needs a `read:packages` PAT as an `imagePullSecret`, which is a second
  credential this decision exists partly to avoid.
- ~~**The four static bundles did not move.**~~ **Resolved the same day by `15-07`/`adr/0051`.**
  `ago-console`, both `ago-demo-shop*` and `ago-landing` were still building on the node under
  `:local` when this ADR was written, because `15-06` could not change those repositories (all three
  had open PRs) — so what closed here was the backend half, while **the 2026-08-25 failure was a
  console bundle**. `adr/0051` publishes all four from their own repositories' CI, under the same
  full-SHA tag and the same no-new-secret mechanism, and makes each serve `/version.json` so a
  running frontend pod can name its own commit the way `/healthz/version` does here. It also answers
  the one question the frontends raise and these three hosts do not: a bundle is configured at build
  time, so an image is only environment-specific if a build *argument* made it so — and `0051`
  removes the argument instead of encoding the environment in the tag.
- **Building on the node is now the exception, not the mechanism.** `redeploy.sh` still builds — for a
  hotfix, or a cluster rebuilt ahead of CI — but it tags what it builds with the commit and the
  registry path, so an image built there and an image pulled from GHCR are interchangeable by name.
- **Every push to `main` permanently publishes three images.** The same trade `adr/0018` made for
  NuGet, and the same answer: it is what a real release process does. Retention is not managed and
  nothing prunes old versions; if that ever matters it is its own item, not a footnote here.
- **CI is slower on `main`** by three image builds. Pull requests are unaffected — they never publish.
- **`kubectl rollout undo` warns about `last-applied-configuration`.** Seen on every rollback during
  the live exercise. It is real: an undo does not update the annotation `kubectl apply` reads, so a
  later `apply -k` reconciles against a stale record. In practice the `images:` block above settles
  it — `apply -k` sets the tag written there regardless — but it is one more reason the committed tag
  and the running tag must be reconciled deliberately rather than assumed equal.
- **Publishing does not deploy.** Out of scope, unchanged from `15-06`'s own framing: this makes
  deploys repeatable and reversible, not automatic. Auto-deploying an environment that holds other
  people's accounts is a separate decision with a separate risk, and nothing asks for it.

## What was actually performed, on the live deployment

Not a procedure written down and never walked. On 2026-08-25, on the real node:

1. Two adjacent real commits of `ago-chat` were built into six images tagged with their full SHAs
   (`4e83908…`, `f3ecc0d…`) and imported into containerd. The three Deployments were switched from
   `imagePullPolicy: Never` to `IfNotPresent`.
2. `./deploy.sh 4e83908…` — rolled out; smoke green on all thirteen pre-existing checks.
3. `./deploy.sh f3ecc0d…` — rolled out; the newer build.
4. `./rollback.sh` — **rolled back to `4e83908…`**, all three hosts, service restored, smoke green.
   `./rollback.sh --history` showed the point of the whole item plainly: revisions 1–6 all read
   `ago-chat-api:local` — six indistinguishable entries with nothing to go back to — and revisions 7
   and 8 name commits.
5. `./deploy.sh 0000…0bad` — a deliberately broken deploy. The new pod went `ErrImagePull` →
   `ImagePullBackOff` and the **old pod kept serving throughout**: `https://chat.reserve-me.ru/healthz/ready`
   answered `200` on every probe for the whole four minutes. A broken *image reference* cannot take
   the site down; only a broken *application* can, and only that one needs a rollback. `./rollback.sh`
   cleared it.
6. `./deploy.sh f3ecc0d…` returned the node to the code it was running before any of this. 18 pods
   Running, 0 otherwise.

The images used were real commits from before this ADR's own branch, so they predate
`/healthz/version` and the pods reported `unreadable` for the commit column — and `smoke.sh` failed
that one check, correctly and by design, saying *"a pre-15-06 image is deployed, and it cannot name
its own commit"*. The identity evidence in this run was therefore the image tag and the resolved
digest read off the running pods. The binary-side mechanism was verified separately and directly:
`dotnet publish -p:SourceRevisionId=433847f9…` produces an assembly whose informational version reads
`1.0.0+433847f94a437963050ad75c752af776a8f61d34`, which is exactly what `BuildInfoResponse` parses,
under nine unit tests.

## Alternatives considered

- **Keep `adr/0026`'s build-on-node and only add tags.** Cheapest possible change, and it would have
  fixed identity — but not durability. The artifact would still exist on exactly one machine, so
  `15-02`'s rebuilt cluster still has nothing to run and `17-04` still has nothing to scan.
- **`sha-<short>` tags.** Shorter and prettier in `kubectl get pods`. Rejected: a short SHA has to be
  expanded before it can be compared to anything, and abbreviations collide as a repository grows.
- **Semantic version tags on the images.** `ago-platform` versions its packages this way for a real
  reason — consumers resolve ranges. Nothing resolves a range of `ago-chat-api`; there is one
  deployment and it wants an exact build. A version number here would be a second name for a commit,
  maintained by hand, able to drift from it.
- **An `imagePullSecret` and private packages.** Works, and is what a closed-source project would do.
  Rejected: it reintroduces the credential `adr/0026` declined a registry to avoid, on a repository
  that is public anyway, to protect bytes that are already public.
- **Argo CD / Flux, or any pull-based deployer.** The honest general answer to "the manifest and the
  cluster drift". Rejected as far out of proportion: one node, one environment, a deploy every few
  days, and a controller of its own to run on a box with ~2 GiB of headroom.
