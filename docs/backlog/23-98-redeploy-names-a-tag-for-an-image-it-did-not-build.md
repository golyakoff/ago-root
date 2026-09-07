# redeploy names a tag for an image it did not build

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `15-21`/`adr/0144` built the drift check that cannot see this, and `23-90`
  is the neighbouring blindness in the same mechanism.
- **Found**: 2026-09-08, by a deploy stopping.

## What happened

`redeploy.sh` closes by printing the tags an operator should commit, so the manifest records what the
cluster runs:

```
ago-chat-{api,worker,webhooks,migrator}   255cbea2e089d08639832343507e1c78ad0f973e
```

Those values were committed verbatim. **`ago-chat-migrator` at that tag was never built.** The node
holds `ago-chat-api`, `ago-chat-worker` and `ago-chat-webhooks` at `255cbea`, and no migrator image at
all; `ghcr.io` has none either. So the next `apply-demo.sh` created a `Job` pointing at an image that
does not exist, which sat in `ImagePullBackOff` and never started a container.

## Why it is worse than one failed Job

**A Job stuck active refuses the next apply.** `apply-demo.sh` reads `.status.active` and declines
rather than killing a migration that might be running — correct behaviour, and here it would have
blocked the following day's deploy on a Job that was never going to start.

**Nothing else was going to notice.** `check-manifest-drift.sh` compares Deployments and
NetworkPolicies and **excludes Jobs deliberately** (`8-08` ties a migrator's tag to its host's, so they
legitimately differ between a deploy and its commit). So the one object whose tag the script tells you
to record by hand is the one object the drift check does not look at.

**And the failure presents late and elsewhere.** Not at the deploy that printed the wrong line, but at
the next apply, as an image-pull error naming a SHA that looks entirely plausible.

## What is not yet established

**Whether the script printed a tag it never built, or built one that was later collected.** Those need
different fixes and the distinction is the first thing to settle — read `redeploy.sh`'s own build loop
and see whether the migrator is in it, before assuming either.

## Scope

- **The closing summary names only images that exist.** Whatever the cause, the printed instruction and
  the artifacts must agree, because an operator following it precisely is what produced this.
- **Or the manifest stops being updated by hand at all** — `23-90` is already the item asking whether
  recording tags should be mechanical, and if it is answered that way this stops being possible rather
  than being caught.

## Where this is likely to go wrong

- **Do not fix it by including Jobs in the drift check.** They are excluded for a stated reason, and
  reversing that would make the check fire on every ordinary deploy — the fastest way to make it
  ignored, which is `23-90`'s whole subject.
- **A deploy that fails loudly is the good case here.** The bad one is an apply that silently rolls a
  host back; keep whatever fails closed, failing closed.

## Done when

- [ ] A tag the closing summary prints is an image that exists, or the summary says which are missing.
- [ ] Whether the image was never built or was collected afterwards is established and written down.
- [ ] The failure mode is demonstrated once — a printed tag with no artifact behind it — rather than
      argued.
