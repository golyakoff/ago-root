# what else AGO does, on a surface addressed to the person who can buy it

- **Stage**: 23
- **Status**: done (2026-09-05). `/settings/products` in `ago-console`, gated on `site:configure`
  (`adr/0106`). Reads `enabledModules` off the same `GET /api/v1/operators/me` response
  `usePermissions()` already resolves (`23-21`) — no new server read. The navigation entry itself
  stays this item's one open question, deferred to `23-24` as scoped below.
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

- [x] An owner sees every product, with the ones their workspace holds marked as held. Three rows
      today: conversations (always held), booking (`enabledModules.includes("calendar")`), automatic
      answers (`enabledModules.includes("faq")`) — see `adr/0106` for why the list stops there
      (AGO Inbox's channels have no equivalent tenant-held fact to read yet).
- [x] An operator without the owner-side permission does not reach this screen — and, per §10 and
      `23-24`, is not offered it in the navigation either. The screen itself refuses (danger `Alert`,
      no product data rendered — proven by a test asserting `fetchBillingStatus`-style non-leak); the
      navigation half is vacuously true today (no entry anywhere points at `/settings/products` yet)
      and stays `23-24`'s own responsibility to keep true once it adds one.
- [x] A product the tenant does not have offers a next step that is true today, with no control that
      appears to provision anything. Prose only ("Contact AGO to add this to your workspace.") — no
      link, matching the existing no-address "contact us" precedent (`InstallSnippetPage`'s own
      `installOriginPanelDescription`) rather than inventing an email this repository cannot verify is
      real or monitored.
- [x] The screen reads in the tenant's language, both `en.ts` and `ru.ts`, with no module key visible
      to a reader. `ux-gate`'s own untranslated-Latin-text assertion runs against this screen
      (`ux-gate/fixtures/screens.ts`'s new `products` entry); a unit test additionally asserts neither
      `"calendar"` nor `"faq"` appears anywhere in the rendered text.
- [x] Nothing on this screen claims a price.

## Open questions

- **Where it sits in the navigation.** Still open, by design — `23-24` owns `consoleNav.ts` and is
  deciding the gated-entry treatment at the same time; this item builds the screen and its route
  (`/settings/products`) and stops there rather than pre-empting that decision. Recommendation for
  `23-24` to weigh: this is the one entry in the whole nav whose audience is the owner rather than the
  operator (§10), so it does not fit `23-24`'s own muted/locked treatment (which exists for a
  capability *the tenant has* that *this operator* cannot use) — an owner who cannot see this screen
  cannot see it because the tenant's own `enabledModules` are irrelevant to its gate, not because a
  colleague could grant something this identity lacks. It sits more naturally beside `/settings/billing`
  in the settings group than among the calendar/FAQ/tag entries above it, gated identically
  (`site:configure`) and requiring no new muted state of its own — a plain shown/hidden entry, the
  same shape every other `site:configure`-gated row in `buildTenantNavItems` already has.
