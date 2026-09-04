# what else AGO does, on a surface addressed to the person who can buy it

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-21` — the tenant's own enabled-module list, which is what tells this screen
  which products are already held. `23-14` is not a dependency but is the owner-side mirror of the
  same facts.
- **Decision**: `docs/design/decisions.md` §10 (2026-09-05), the *navigation is not a sales surface*
  half; §6 for how a grant is actually made today

## Goal

A tenant owner can see which products exist, which of them their workspace already has, and what to
do about the ones it does not — in one place that is addressed to them.

## Why this is a screen and not rows in the navigation

§10's reasoning, restated because it is the whole justification for a separate surface: an entry
drawn for a capability the tenant has not bought is a price list the reader usually cannot act on.
The operator seeing it cannot buy, and the owner who can already holds the permissions in question
and therefore already sees those entries. So the greyed row has no commercial value to the only
person who could act and costs clarity for everyone else.

The consequence is not "hide it and hope". It is that **the same information needs an audience of its
own**, and this is it.

## What is actually true today, verified

- A tenant's own console has no screen naming a product it does not hold. `/settings` lists what is
  enabled (`23-01`'s site-scoped read); nothing lists what exists.
- Enabling a product is not self-service. `22-17`'s API is owner-only and §6 keeps `/owner`
  read-only for now, so the honest next step this screen offers is a conversation, not a button that
  pretends to provision.
- `23-21` put the tenant's enabled-module list on `GET /api/v1/operators/me`, so *which of these do we
  already have* is answerable without a new read.

## Scope

- A screen listing the products this platform offers, each marked with whether this workspace has it,
  gated on the permission an owner holds rather than shown to every operator.
- For a product the tenant does not have: **what it does, in the tenant's own terms**, and a next
  step that is true — reaching AGO. Not a checkout, not a trial toggle, not a "request access" that
  writes nothing.
- For a product the tenant has: say so, and link to where it is used, so the screen is useful to
  somebody who already bought rather than only to somebody who has not.
- The copy names what the product does for the tenant's customers, not the module key. `calendar` is
  a word from our schema; *taking bookings* is the thing being sold.

## Out of scope

- **Self-service purchase, pricing and billing.** None of it exists, and inventing a price on a
  screen is worse than naming none. When it does exist this screen is where it lands, which is why
  it is a screen rather than a paragraph on `/settings`.
- Provisioning from the tenant side — that is owner-only by §6, and changing it is its own decision.
- The `/owner` side of the same facts (`23-14`).
- Anything in the navigation. §10 settles that: this surface exists precisely so navigation does not
  have to carry it.

## Done when

- [ ] An owner sees every product, with the ones their workspace holds marked as held.
- [ ] An operator without the owner-side permission does not reach this screen — and, per §10 and
      `23-24`, is not offered it in the navigation either.
- [ ] A product the tenant does not have offers a next step that is true today, with no control that
      appears to provision anything.
- [ ] The screen reads in the tenant's language, both `en.ts` and `ru.ts`, with no module key visible
      to a reader.
- [ ] Nothing on this screen claims a price.

## Open questions

- **Where it sits in the navigation.** It is the one entry whose audience is the owner rather than
  the operator, and `23-24` is deciding the treatment for gated entries at the same time. Settle it
  with that item rather than separately, or the two will disagree.
