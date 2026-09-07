# the reveal item names four screens and there are now five

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-30`, whose scope this corrects. `23-34` is the screen it missed.
- **Found**: 2026-09-07, while settling `23-34`'s Done-when.

## The gap, in one sentence

`23-30` — *the calendar console reveals a masked number on demand* — enumerates **four** screens:
queue, contacts, worker slots, recut preview. **`23-34` shipped a fifth**, the confirmed-bookings list,
which renders a masked phone and has no reveal control.

`23-34` did not exist when `23-30` was written, so this is a scope that went stale rather than a scope
that was wrong.

## Why it needs a number rather than an edit

Because of what happens if it does not get one. `23-30` ships as currently scoped, four screens gain a
reveal, everyone treats reveal as delivered — and `23-34`'s second Done-when is **still false**, on a
screen nobody is looking at any more. A masked number with no way to reveal it is not a security
property; it is a screen an operator cannot do their job from, and the reason will be invisible.

An enumerated scope is a promise that the enumeration is complete. When it stops being complete, saying
so out loud is cheaper than discovering it from a support call.

## Scope

- **Either widen `23-30` to five screens before it is built, or make this the fifth.** Widening is
  probably right — one reveal control, five callers, one audit record — but that is a judgement about
  `23-30`'s size and belongs to whoever picks it up.
- **Whichever way, `23-34`'s second box closes with it**, and this item names that explicitly so the
  link is not lost again.

## Where this is likely to go wrong

- **The audit record is the point, not the reveal.** `23-34`'s box says *revealing it writes the same
  record* — the same one, not a similar one. A fifth screen with its own reveal path that writes a
  differently-shaped record satisfies the sentence and defeats it.
- **There may be a sixth.** The lesson generalises: check the screens that render a masked number at
  the time `23-30` is built, rather than trusting either enumeration.

## Done when

- [ ] Every console screen that renders a masked calendar phone can reveal it, or is listed with a
      reason why not.
- [ ] The reveal writes one record shape, wherever it is triggered from.
- [ ] `23-34`'s second Done-when is true.
