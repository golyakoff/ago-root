# The demo pages still say there is one shared tenant, and the widget contradicts the button

- **Stage**: 8
- **Status**: ready
- **Depends on**: `8-09` — merged and deployed, and this is what deploying it made false.

## What is wrong

`8-06` wrote the demo pages' honesty copy when there was one shared tenant and one published operator
login. `8-07` and `8-09` made that untrue, and the copy did not move. Two of them are visible to a
stranger inside one minute, and one of them is a direct contradiction rather than staleness.

Found by walking the live demo end to end on 2026-08-26.

### 1. The widget tells a minted visitor their private conversation is public

This is the one that matters. On a tenant minted from the button, on that tenant's own
`?site=` page, the widget panel still says:

> This is a public demo. Anyone who opens the demo operator console can read what you type here. Do
> not type anything real.

The panel that handed out those credentials, one click earlier, said:

> Your own tenant is ready. **Nobody else can see its conversations.**

Both are on screen in the same minute. One of them is wrong, and the reassuring one is the true one —
which is the worse way round: a visitor who believes the widget will not use the feature, and a
visitor who believes the panel is right to.

The mechanism is that `demo-boot.js` sets `data-public-demo="true"` unconditionally, so the notice is
attached to the page rather than to the tenant. It should follow the tenant: the shared site is
public, a minted one is not.

### 2. "This deployment holds exactly one tenant"

The page's *Is this safe to poke at?* card says:

> This deployment holds exactly one tenant - this demo site - and nothing else. … this server was
> never given a second, real tenant's data to isolate you from.

There are two seeded tenants (`demo-shop1`, `demo-shop2` — and demonstrating isolation *between* them
is what `8-05` put them there for), plus one minted tenant per viewer who presses the button.

The card's underlying reassurance is still true and worth keeping: **nothing here is real customer
data.** But it currently argues that by claiming a fact about tenant count that stopped being true,
and a reviewer who notices will discount the rest of the card with it.

## Why this is its own item rather than a fix folded into something else

The copy is the product's honesty, on the page a reviewer lands on first. Both sentences were correct
and carefully argued when written, and both were falsified by a feature landing rather than by
anybody being careless. That pattern is worth one item that fixes them together and says what makes
copy like this go stale, instead of two one-line edits.

## Context to read first

`docs/backlog/8-06-*` — the notice and its reasoning, which is still sound and is not being reversed
here. `docs/adr/0058-*` — what a minted tenant actually guarantees, which is what the widget's notice
has to become conditional on. `ago-widget/src/demo/boot.ts` — where `data-public-demo` is set.
`ago-widget/public-demo/index.html` and `public-demo-2/index.html` — the cards.

## Scope

- **The public-demo notice follows the tenant, not the page.** On a minted tenant it should either be
  absent or say something true about that tenant — the second is better, because "your conversation
  is private and this tenant disappears in a day" is worth saying and is not said anywhere in the
  widget today.
- **Rewrite the safety card** so its reassurance rests on what is true: no real customer data exists
  on this deployment, and the tenants that exist are demo ones. Do not simply change "one" to "two",
  which goes stale again on the next minted tenant.
- **Check the rest of both pages for the same class of staleness** while there — including the top
  banner's "the operator login below is published on this page, so anyone can read every conversation
  started here", which is now true only of the shared login.
- Both pages, both languages wherever the landing page mirrors this.

## Out of scope

- Removing the shared `demo-operator` login or the seeded tenants. They demonstrate isolation and
  `8-09` deliberately kept them.
- `5-18` — the console's hub connection. Unrelated, and far more serious.
- Any change to `8-07`'s endpoint or `8-09`'s panel, both of which say true things.

## Done when

- [ ] On a minted tenant, no text anywhere on the page or in the widget says that anybody else can
      read the conversation.
- [ ] On the shared demo page, the notice is unchanged — the warning is still needed there, and this
      item must not weaken it.
- [ ] The safety card makes no claim about how many tenants exist.
- [ ] Verified in a browser on both pages, in both states, rather than by reading the source.

## Open questions

**Whether the widget should say anything at all on a minted tenant.** Silence is defensible: the
panel already said it. But the widget is the surface a visitor is actually looking at while typing,
and `8-06`'s original argument — that the warning belongs where the typing happens — applies just as
well to the reassurance.
