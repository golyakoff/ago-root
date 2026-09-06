# nothing re-runs the tenant-isolation scan, so its headline numbers drift again

- **Stage**: 24
- **Status**: ready
- **Depends on**: nothing. `22-19` built the scan; this is about what makes anyone run it.
- **Decision**: taken by the author 2026-09-06 — each backend computes its own numbers by reflection and serves them; the console sums them; visible to the platform owner only

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

## The decision, taken by the author 2026-09-06

**Each backend computes its own numbers at runtime, by reflecting over its own handlers, and serves
them. The console adds them up.** Not a script reading source text from outside, and not a CI check in
`ago-chat`.

The author ruled out the CI shape for a reason worth keeping: it would need the same check in
`ago-calendar` too, and it makes one repository's build depend on a file in another that it cannot see.

**And the measurement removed the argument the other two rested on.** The scan takes **1.5 seconds**
end to end — 0.8 to export the tree, 0.6 to run both scripts. It reads source text; there is no build
and no test. So "run it rarely because it is expensive" was never a real constraint, and the choice
came down to *where the number should live* rather than what it costs.

### Why runtime is more honest than the script, not merely different

The script infers the numbers from **source text**. The application can answer from **itself** —
`Ago.Chat.Architecture.Tests.TenantScopeTests` already walks the IL of every handler to enforce this
invariant at build time, so the same reflection at startup reports a fact about the assembly that is
actually running rather than about a checkout somebody may not have.

That closes the drift by construction. A number that is *computed* cannot go stale; a number that is
*written down* always can, which is what this item exists because of, twice.

### It is shown to the platform owner and to nobody else

Also the author's call, and the reason matters: **"47 entry points that do not check permissions" is a
hint for somebody looking for a way in.** It goes on `/owner`, behind the realm role no write in this
codebase grants — not to tenants, and not in any anonymous response.

## Scope

- Each backend exposes its own counts — entry points, RBAC-gated, exempt, and the routes figures —
  computed at runtime from its own handlers, not read from a committed file.
- The console reads both products and shows one combined figure, on `/owner` only.
- **It must distinguish "the numbers moved" from "a handler is ungated".** Those are a documentation
  chore and a security finding, and a display that shouts equally about both will be ignored for the
  first reason and then miss the second. `Unaccounted` is the field that carries the distinction and it
  should be impossible to miss when it is not zero.
- Refresh the five counts in `tenant-isolation.md` as part of this item, so it does not land describing
  a state it also leaves.
- **Say in `tenant-isolation.md` that the table is now a snapshot of a live figure**, with where to read
  the live one. A document that looks authoritative and is second-hand is how this drifted the first
  two times.

## Out of scope

- Changing what is measured, or the approximation of "RBAC-gated". `22-19` settled that, and it
  currently produces `Unaccounted: 0`, which is the evidence it is good enough.
- Retiring `tools/tenant-isolation-scan/`. It stays: it is the only thing that can measure a *checkout*
  rather than a running deployment, which is what a reviewer reading the repository has.
- Any change to isolation itself. Nothing here suggests a hole.

## Done when

- [ ] Each backend serves its own counts, computed at runtime from its own handlers.
- [ ] `/owner` shows one combined figure, and nothing anonymous or tenant-facing exposes it.
- [ ] A non-zero `Unaccounted` is visibly different from a count that merely moved.
- [ ] `tenant-isolation.md`'s five counts match reality on the day this lands, and the file says the
      table is a snapshot rather than the source.

## What this deliberately does not solve

**Nothing here catches drift while nobody is looking at the screen.** A runtime figure is correct
whenever it is asked and silent when it is not, which is a different property from a check that fires
on its own. The author's separate decision — that "loss and forgot" checks should run **every 12
hours** — is `25-03`, and the two are complements rather than alternatives: this one makes the number
impossible to get wrong, that one makes somebody look.
