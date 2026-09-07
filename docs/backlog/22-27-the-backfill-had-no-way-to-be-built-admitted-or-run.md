# the backfill had no way to be built, admitted, or run

- **Stage**: 22
- **Status**: done (2026-09-04), `ago-deploy@bc55af0`. Written retrospectively on 2026-09-07 — see
  `22-29`, which also covers `22-26`.
- **Found**: 2026-09-04, running `22-16`'s backfill on the node, immediately after `22-26` fixed the
  first of the three reasons it could not run.
- **Note on the record**: this item never had a GitHub issue, in either repository. It exists only as
  the commit below. That is why nothing in `ago-root`'s queue ever named it, and why it is being
  written up three days after it shipped rather than at the time.

## Written retrospectively, from the commit alone

There is no issue to read and no other document that mentions this by number. Everything below comes
from `ago-deploy@bc55af0` — `fix(22-27): the backfill has a way to be built, admitted and run` — and
from reading the three files it changed. Nothing here is inferred beyond what that commit message and
its diff say.

## What was actually true

With `22-26` fixed, the backfill's image could be built — but nothing on the node had a way to build
it, get it past the database's network policy, or run it more than once by hand. Running `22-16`'s
backfill on 2026-09-04 found the remaining two of the three reasons it could not run at all:

- **Absent from `build-images.sh`.** The script named only the four serving hosts. Nobody had built the
  backfill's image before this, which is also why `22-26`'s missing `COPY` line went unnoticed for the
  six hours the host existed — nothing had ever tried.
- **Absent from the `postgres-ingress` NetworkPolicy.** The pod failed with `Failed to connect` against
  a Postgres that was accepting connections from everything the policy actually admitted. The commit
  message calls this the identical failure `8-08`'s migrator hit on 2026-08-26, on a page
  (`docs/architecture/edge.md`, per that item) that already carried the sentence "adding a workload
  that talks to Postgres means adding it here" — the lesson was written down and relearned anyway,
  because nothing checks the policy's admit-list against what actually exists; it is a hand-kept mirror
  of a fact that lives in the manifests.

And there was a fourth gap the commit treats as part of the same fix rather than a separate cause: no
way to run the backfill that anyone could repeat.

## What shipped

`ago-deploy@bc55af0` — `fix(22-27): the backfill has a way to be built, admitted and run`:

- **`k8s/build-images.sh`** — `Ago.Chat.RoleAssignmentBackfill` joins the four names already built.
- **`k8s/overlays/demo/network-policies.yaml`** — `ago-chat-roleassignment-backfill` joins the
  `postgres-ingress` admit-list, with a comment naming `8-08`'s identical failure as the reason this
  list needs a manual entry per workload that talks to the database.
- **`k8s/run-backfill.sh`** (new, 111 lines) — deliberately **outside** `overlays/demo`: the backfill is
  a one-shot corrective, not a step of every deploy, and a Job living in the overlay would be recreated
  and re-run by every `apply-demo.sh`. It resolves the image tag from what `ago-chat-api` is actually
  running (so the backfill runs the hosts' own commit, not a remembered tag) and the credentials
  secret's name from the migrator Job (because kustomize's content hash in that name can never be
  written down statically). The pod's `app` label is `ago-chat-roleassignment-backfill` — the value the
  policy now admits, chosen deliberately over borrowing the migrator's label, which would also have
  worked but would have made this pod answer to `-l app=ago-chat-migrator` for anyone who greps for one.

## Why nothing caught it before this

None of it is something a test or CI job run against source could see: a missing entry in a shell
script's build list, a missing entry in a Kubernetes manifest, and the absence of a runnable script are
all facts about the deployment surface, not the code. The NetworkPolicy gap in particular is exactly
the failure mode `8-08` had already named in prose — the commit message is explicit that being written
down did not stop it from happening again, because nothing mechanical reads that list against reality.

## What is not recoverable

Nothing records whether `build-images.sh`'s four-name list and the NetworkPolicy's admit-list were
checked against `Ago.Chat.RoleAssignmentBackfill` at any point before this run and found (wrongly) to
be fine, or simply never checked. The commit message states what was found and fixed, not what was
looked at beforehand.

## Out of scope

- `22-26` — the Dockerfile half of the same afternoon, shipped as a separate `ago-chat` commit under
  its own number.
- Actually running the backfill to completion and counting its effect, which `22-16`'s own Done-when
  asked for and which the trail stops short of — carried out to `22-28`.
- Putting the backfill's Job into the overlay so it runs on every deploy. The commit message states
  this was rejected deliberately: it is a one-shot corrective, not a step of deploying.

## Done when

- [x] The record exists: what the two remaining gaps were, why neither was caught earlier, what
      shipped, and that no GitHub issue for this number ever existed.
