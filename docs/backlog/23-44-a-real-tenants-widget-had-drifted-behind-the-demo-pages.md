# a real tenant's widget had drifted behind the demo pages, and three mechanisms missed it

- **Stage**: 23
- **Status**: done (2026-09-06). Corrected on the stand, the two deploy scripts fixed, and the
  invariant now checked by `smoke.sh` rather than asserted in a comment.
- **Depends on**: nothing
- **Decision**: none. This is a defect, found while doing something else.

## What was true

`ago-widget-assets` is the image behind `chat-api.reserve-me.ru/widget/widget.js` — **the URL the
install snippet hands a real tenant.** It was serving `ac79181` while both demo pages served
`003af21`: a bundle **7KB smaller**, missing `23-07`'s beacon and everything else merged in between.

Nothing was broken and nothing leaked. **The tenant-facing widget simply was not the thing anybody
had tested, deployed or looked at**, and had not been for some time.

Found by accident, while pinning the running image tags at the author's request. Nothing was looking
for it, because nothing could.

## Three mechanisms missed it, and the order matters

- **`redeploy.sh` built and imported this image on every run, then rolled four Deployments and not
  this one.** Absent from that loop since `15-07`.
- **`deploy.sh` could not move it by name at all**, because it was not in `FRONTENDS` — which also
  meant `--current`, the command whose entire job is answering *"what is running"*, printed no row for
  it. **That is why the first miss stayed invisible**: the tool built after the 2026-08-25 stale-bundle
  incident, specifically so that a deploy would be identifiable, had a blind spot exactly the shape of
  the thing it was built to catch.
- **`smoke.sh`** checked that the URL serves JavaScript and 404s a nonsense path, but never *which
  build*.

Meanwhile the kustomization comment above those three images has asserted the invariant since
`15-07` — one `ago-widget` commit, byte-identical bundles, *"checkable (three `version.json` files
naming one commit) instead of assumed"*. **Nothing checked it.** The word "checkable" is doing a lot
of work in that sentence and it turns out to have been the whole of it.

## The lesson, which is not "add the image to the list"

An invariant written in a comment is a hope. This one was written by somebody who had just thought
carefully about it, in the right file, next to the right lines — and it still decayed, because the
comment cannot fail.

**The guard belongs where a mismatch shows, not where it is introduced.** So the check is in
`smoke.sh`, comparing the commit a tenant's bundle carries against the demo page's own — not in the
deploy scripts, because a script can only promise what it does. Asking what is actually being served
also catches a hand-rolled `set image`, a rollback of one image and not the others, and the next
mechanism nobody has thought of yet.

## Done when

- [x] The stand serves one build to tenants and demo pages alike.
- [x] `redeploy.sh` rolls the image it has been building all along.
- [x] `deploy.sh --current` prints a row for it, so it can never again be invisible to the tool whose
      job is visibility.
- [x] `smoke.sh` fails when the two bundles disagree, proven by rolling the stand back and forward.
- [x] Every `newTag` names what is actually running, verified by rendering the overlay and reading
      the images back rather than by trusting the edit.

## Out of scope

- Serving one image instead of three copies of one bundle. That is a real question — three images
  built from one commit exist so the demo pages carry their own copy — but it is a change to how the
  widget is delivered, not to whether the three agree, and it needs its own argument.
