# nothing re-runs the tenant-isolation scan, so its headline numbers drift again

- **Stage**: 24
- **Status**: ready
- **Depends on**: nothing. `22-19` built the scan; this is about what makes anyone run it.
- **Decision**: none yet — the open question below is a real choice, not a formality

## Goal

The five headline counts at the top of `tenant-isolation.md` are true on the day somebody reads them,
without anybody having to remember to check.

## What is actually true today, verified 2026-09-06

`tools/tenant-isolation-scan/` was filed by `22-19` **because those counts had drifted for ten stages
without anyone re-running the scan that produced them**. The tool works. It has drifted again anyway.

Run against `origin/main` on 2026-09-06, it reports:

| Count | `tenant-isolation.md` says | The scan says |
|---|---|---|
| Use-case entry points | 113 | **130** |
| Handler classes | 105 | **119** |
| RBAC-gated | 76 | **83** |
| Routes and hub methods carrying tenant data | 110 | 110 |
| Routes taking a client-supplied `siteId` | 45 | **52** |

Four of the five are wrong. The fifth is right by coincidence rather than by maintenance — the
composition behind it has changed even though the total has not, which is the more dangerous shape,
because a reader who spot-checks that one row concludes the table is maintained.

`Unaccounted: 0` in both runs, so this is **not** a gap in coverage — every entry point is still
either gated or on the exemption list. The numbers are stale, not the isolation.

## Why this is a gap rather than an oversight

It is the identical failure `24-14` found in `secrets.md` a day earlier, and the identical remedy
worked there: a file whose value is *completeness*, with nothing mechanical keeping it complete,
drifts on exactly the schedule of the work that changes it. `22-19` built the measuring instrument and
stopped there — which was the right size for `22-19`, and leaves this.

The comparison worth making: `personal-data.md` has stayed true through the same period, because four
separate places name it and make a change that widens the map a change that has to think about it.
`tenant-isolation.md` has one tool and no caller.

## Scope

- Something that fails, or is impossible to skip, when the counts stop matching the source.
- Whatever that mechanism is, it must distinguish **"the numbers moved"** from **"a handler is
  ungated"**. Those are a documentation chore and a security finding respectively, and a mechanism
  that shouts equally about both will be muted for the first reason and then miss the second.
- Refresh the five counts as part of this item, so it does not land describing a state it also leaves.

## Out of scope

- Changing what the scan measures, or its approximation of "RBAC-gated". `22-19` settled that and the
  approximation currently produces `Unaccounted: 0`, which is the evidence it is good enough.
- Any change to isolation itself. Nothing here suggests a hole; see the note above.

## Done when

- [ ] The five counts match a scan run on the day the item lands.
- [ ] Something mechanical fails when they stop matching.
- [ ] A newly ungated handler is distinguishable, at a glance, from a count that merely moved.

## Open questions

- **Where does the mechanism live, and what does it cost?** Three shapes, and they trade differently:
  - **A CI check in `ago-chat`** fails the PR that moves the numbers. Strongest, and the one that
    catches it at the moment of the change — but it puts a check on `ago-chat` that fails because a
    file in *`ago-root`* is stale, which is a cross-repository coupling this project has otherwise
    avoided, and `ago-chat`'s CI cannot see `ago-root` at all today.
  - **A check in `ago-root`'s own `tools/queue-audit.sh`**, the way `24-14` put the secrets sweep in
    `tools/secrets-audit.sh`. Cheap, already run at every landing, no new coupling — but it only fires
    when somebody lands an `ago-root` change, so a run of pure `ago-chat` work drifts silently until
    the next one.
  - **Naming the file in the skills that accompany the changes that move it**, the way
    `personal-data.md` is named in four places. Cheapest and weakest: it is the mechanism that already
    failed once here, since `22-19` is cited in this file and did not stop the drift.
  The author's call. `24-14` chose the middle shape for the analogous problem, and it has not yet had
  time to prove itself.
