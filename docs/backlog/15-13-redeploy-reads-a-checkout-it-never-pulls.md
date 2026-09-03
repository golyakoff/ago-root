# Pull every checkout whose commit `redeploy.sh` reads

- **Stage**: 15
- **Status**: ready
- **Found**: 2026-09-03, by the worker implementing `20-26` — which added the two calendar checkouts
  to the very loop this is missing from. It named the gap and correctly did not fold it in: different
  product, different promise. Confirmed against the live node afterwards.

## The gap

Step 1 pulls six checkouts:

```
for d in ago-platform ago-chat ago-console ago-widget ago-calendar ago-calendar-console ago-deploy
```

`ago-landing` is not among them. Further down, its commit is read anyway:

```
LANDING_SHA="$(git -C "$AGO_ROOT/ago-landing" rev-parse HEAD)"
```

So a build-from-source run tags the landing image with whatever that checkout happens to be sitting
on, builds from it, and rolls it out — while every other component is built from its tip.

## Why it matters more than a stale bundle

This is the precise failure step 1 exists to close, and the script's own header tells the story: on
2026-08-25 `ago-console` was six commits behind on this box and had been serving a stale bundle for a
day with nothing reporting it.

**But the tag makes this one worse.** The image is *labelled* with the stale SHA, and `smoke.sh`
compares the running tag against the commit inside the artifact. Both would agree. The check would
pass while the apex domain served old content — a tag that is honestly wrong defeats every check
built on tags, which is most of them.

**Live, not hypothetical.** On 2026-09-03 the node's `ago-landing` was **14 commits behind**, beside
`ago-chat` at 85 and `ago-console` at 71. The other two are in the pull loop and would have corrected
themselves on the next run. Landing would not have.

## What this must produce

- `ago-landing` joins the pull loop, so its SHA is read from the same tip every other component's is.
- **One pass over the two lists.** The directories pulled and the `*_SHA=` assignments should agree,
  and something should say so — a check, or at minimum a comment that makes the pairing visible.
  This gap survived because the two lists sit ninety lines apart and nothing relates them.

## Done when

- [ ] `redeploy.sh` pulls every checkout whose commit it reads.
- [ ] Proven by leaving a checkout deliberately behind and showing the run corrects it rather than
      building from it.
