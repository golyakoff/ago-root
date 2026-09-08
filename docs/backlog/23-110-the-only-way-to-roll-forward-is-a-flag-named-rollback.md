# the only way to roll forward is a flag named rollback

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing. `22-24` added the guard this is about, and the guard is right to exist.
- **Found**: 2026-09-08, deploying the day's accumulated work to the demo stand.

## What happened

`apply-demo.sh` compares the manifest's pinned tags against what is running and refuses when the
manifest names a tag nothing is running:

> this apply would move these to a tag nothing is running: … Refusing to apply. If a redeploy just
> ran, the manifest is behind the cluster … If you really do mean the tags in the file:
> `./apply-demo.sh --force-rollback`

That guard is `22-24`, and it is correct. The failure it prevents is real and expensive: a
`redeploy.sh` run moves the cluster forward without editing any file, so the committed manifest is
then *behind* the cluster, and the next innocent `apply -k` silently rolls production back.

**But the comparison cannot tell that case from its opposite.** A manifest deliberately bumped to
freshly published CI images is also "a tag nothing is running" — and that is a roll *forward*, the
ordinary way this stand is meant to be updated. Both look identical to the check, because both are
"the file names something new".

## Why the naming is the defect, not the guard

The escape hatch is spelled `--force-rollback`, and its own comment says it "keeps a deliberate
rollback possible while an accidental one is not". Mechanically it does nothing but skip the refusal.
So today, **the only way to roll forward from a committed manifest is to type the word `rollback`**.

That matters for a specific reason and not as a matter of taste: shell history and runbook transcripts
are read later, by somebody reconstructing what happened during or after an incident. A line reading
`./apply-demo.sh --force-rollback` in the history of a day when nothing was rolled back is a false
statement in the most-consulted record there is. The guard's whole value is that somebody stopped and
thought; a flag that misdescribes what they decided spends that value immediately.

## What is genuinely undecided

The obvious fix — a second flag, `--roll-forward` or `--i-mean-these-tags` — is one line, and would
have made this deploy honest. The question underneath it is whether the script should stop guessing at
all:

1. **Two flags, one gate.** Both spellings skip the same check; the operator's word appears in the
   history. Smallest change; does nothing to help the operator decide which they are doing.
2. **The script works it out.** It has enough information — the running tags are commits, and it can
   ask git whether the manifest's tag is a *descendant* of what is running. Then forward is
   detected and allowed, and only a genuine rollback needs a flag at all. Costs the script a
   dependency on the checkouts being present and current, which `redeploy.sh` guarantees and
   `deploy.sh` does not.
3. **The order of operations changes instead.** The runbook already says to deploy first and record
   the tags afterwards; this whole situation came from doing it the other way. Make the manifest
   record what was deployed rather than a request for what should be, and the manifest is never
   ahead. Cheapest of all — but it removes the ability to describe an intended state before applying
   it, which is the point of a committed record.

## Where this is likely to go wrong

- **Do not weaken the refusal to fix the naming.** The 2026-08-25 incident this guard descends from
  is what an unguarded apply costs; a flag that is easy to type is fine, a check that is easy to
  bypass silently is not.
- **`check-manifest-drift.sh` carries the same comparison** and would need whatever is decided here,
  or the two will disagree about what drift means.
- **Reading 2's descendant test is not free of edge cases** — a force-push, a rebuilt branch, or a
  tag from a repository the node has not fetched all read as "not a descendant", and failing closed
  there means refusing legitimate forward deploys.

## Done when

- [x] A roll-forward now needs no flag at all, so there is no word to type. The script classifies
      each introduced tag by asking the cluster what it has already run, and only a detected rollback
      reaches `--force-rollback` - which makes that name true rather than merely tolerable.
- [x] Shown, against the live cluster, with nothing applied - `--check-only` was added for exactly
      this and the guard had never been provable before. Five cases: an unchanged manifest passes; a
      never-run tag moves forward at exit 0 where it used to be refused; a previously-run tag is
      refused at exit 1; the same with `--force-rollback` continues; and an apply carrying both
      directions refuses on its rollback half.
- [x] They agree. The drift checker's advice said apply refuses "while the committed pins are behind
      the cluster", which stopped being true; it now says apply refuses a *rollback*, and that a
      manifest deliberately ahead is a roll-forward needing no flag. The two scripts already had to
      share an image-name regex (`15-22`); this is a second coupling and both files say so.
