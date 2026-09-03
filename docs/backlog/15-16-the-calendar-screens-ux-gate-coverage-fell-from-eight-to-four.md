# the calendar screens' ux-gate coverage fell from eight to four when the console merged

- **Stage**: 15
- **Status**: done (2026-09-04), `ago-console#98`
- **Found**: 2026-09-04, reviewing `22-06` — and reported by that work's own author rather than
  discovered afterwards, which is the only reason it is a ticket instead of a silent loss.

## The gap

`ago-calendar-console`'s own gate covered **all eight of its routes**: queue, setup, workers,
worker-slots, worker-recut, availability, contacts, access. Its fixture header says why — it had few
enough screens that all of them mattered, and three had no other way of being looked at at all.
`15-12` then made that gate **blocking**.

After the merge into `ago-console`: Access is gone entirely (`22-05` deleted the endpoints behind
it), so five screens remain, and the gate covers **four**.

| | before | after |
|---|---|---|
| routes that exist | 8 | 5 |
| covered by a blocking gate | 8 | 4 |

## What is and is not defensible

**`/calendar/setup` is correctly excluded.** It renders an embed snippet as literal `<pre>` text, and
the gate's no-untranslated-text assertion would flag raw HTML wholesale. `InstallSnippetPage` is
excluded from the same gate for the identical reason and says so. That one is settled.

**The two drill-downs — worker-slots and worker-recut — are the real loss.** They were covered;
they are not now. `ago-console`'s gate deliberately curates a handful of screens out of seventeen and
already leaves comparable drill-downs uncovered, so the reduction is *consistent with the host
repository's convention* — but consistency with a convention is not the same as the coverage a
blocking gate had yesterday.

Drill-downs are also exactly the shape the old fixture's own note was about: reached through another
screen rather than from a menu, so nobody stumbles on them.

## Done when

- [x] Either the two drill-downs are back under the gate, or the reduction is a recorded decision
      with its reason. — **back under it.** They were never part of this repository's own five-screen
      accounting to begin with, being the same drill-down-with-no-nav-entry shape `/conversations/:id`
      already has, so restoring them changed neither that accounting nor its single exclusion.
- [x] The count is stated honestly wherever the gate describes itself. — the denominator throughout
      is five, with one exclusion, and no "four of six" phrasing survives.

## Worth expecting

A drill-down that renders a schedule grid is the shape that fails the overflow assertion on mobile.
If it does, that is **a finding about the screen, not a reason to drop the screen** — `22-06` already
found a 22.5px target-size defect exactly this way, in row links that looked fine to the eye.

## Outcome

Done 2026-09-04, `ago-console#98`. The gate went from 33 passed / 5 skipped to **37 / 5** — two screens
on two viewports.

**Standing a screen up found a real gap on its first run**, which is what this item predicted and the
best argument for it: `calendar-worker-slots` renders the seeded calendar's IANA zone id as plain
text, and the no-untranslated-text assertion flagged it. Fixed with an **audited literal** on the
existing exemption list — the same one `ago-calendar-console`'s predecessor gate carried for this exact
screen before the move dropped it — and deliberately not a shape-based pattern, which that file's own
header explains is the trap rather than the fix. No assertion was weakened.

That is the second time in two days this gate caught something invisible to the eye; `22-06` found
22.5px row links the same way.

**Not covered, and said rather than implied**: the recut screen is exercised in its initial form state
only. Driving it to its richer day-preview state would mean teaching `openScreen` a post-navigation
interaction step, which no screen in this gate does today.
