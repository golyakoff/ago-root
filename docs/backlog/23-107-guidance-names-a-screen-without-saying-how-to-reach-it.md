# guidance names a screen without saying how to reach it

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `23-106` is the neighbouring copy problem on the same screen.
- **Found**: 2026-09-08, by the author, following the instruction and not knowing where to go.

## What the tenant reads

On the calendar's staff screen, with the add button disabled:

> Сначала добавьте календарь на экране «Настройка» - у сотрудника ровно один.

The author's response was that they did not understand what it meant.

**Two separate failures in one sentence.** It names a destination — «Настройка» — without saying how to
reach it, and there is more than one screen a tenant could read that as. And it explains the
constraint in the same breath as the instruction, so the actionable half and the reasoning half
compete for the same glance.

## Why the placement makes it worse

The sentence renders in `ago-meta` — the smallest, greyest text on the page — **below** the disabled
button it explains. So a tenant arriving for the first time sees an empty table and a dead control,
and the explanation is the least prominent thing on screen.

For a screen somebody reaches once, at the moment they are trying to start, that ordering is
backwards: the explanation should be more prominent than the thing it explains, not less.

## The author's own instruction, which generalises

> if you advise doing something somewhere, write the full breadcrumb to the section, and how to get
> there through our own menu item.

That is a rule for every piece of guidance in the console, not only this string. **A screen name alone
is not a path**, and the person reading it is by definition somebody who does not know the product.

## Scope

- **This sentence names the route through the menu**, in the words the menu itself uses, so the tenant
  can follow it without guessing.
- **The guidance is more prominent than the disabled control**, not a footnote under it.
- **Find the others.** This is one instance of a pattern; any string that tells a tenant to go
  somewhere is in scope, and the sweep is the deliverable rather than the single fix.

## Where this is likely to go wrong

- **A hard-coded path drifts from the menu.** If the breadcrumb is written as prose and the nav is
  renamed, the instruction quietly becomes wrong — the same class of staleness `23-101` found in a
  document. Deriving the label from the same source the nav uses is worth considering.
- **A link is better than a description, where one is possible.** Naming the route is the floor, not
  the ceiling; a tenant who can click gets there whatever the menu is called.
- **`23-106` renames the noun in this same sentence.** The two items touch the same string, so
  whichever lands second must not undo the first.

## Done when

- [ ] A tenant told to go somewhere can get there without knowing the product.
- [ ] The guidance is not the least prominent element of the screen it appears on.
- [ ] Other guidance strings naming a destination are found and listed, whether or not all are fixed.
