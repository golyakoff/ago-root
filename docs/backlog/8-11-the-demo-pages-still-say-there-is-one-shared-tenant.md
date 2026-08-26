# The demo pages still say there is one shared tenant, and the widget contradicts the button

- **Stage**: 8
- **Status**: done
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

- [x] On a minted tenant, no text anywhere on the page or in the widget says that anybody else can
      read the conversation.
      (Three places, not one. The widget's notice, the page's top banner, **and** the safety
      card's own privacy paragraph - the third was found by walking the built page in a browser
      after the first two were already fixed, which is precisely what the last Done-when is for.
      Checked by collecting `document.body.innerText` plus the shadow root's `textContent` and
      asserting that none of seven phrases from the old copy survives. Held as a test too:
      `leaves no text on the page claiming anybody else can read the conversation`.)
- [x] On the shared demo page, the notice is unchanged — the warning is still needed there, and this
      item must not weaken it.
      (Not a word changed, on either shop. Asserted by string equality against `8-06`'s exact
      sentence rather than by a `toContain`, so a softening edit fails rather than passing on a
      surviving fragment - `renders 8-06's warning word for word on a public demo tenant`, plus
      the same equality check run in the browser on both pages.)
- [x] The safety card makes no claim about how many tenants exist.
      (It now rests on “every tenant here is a demo tenant, no real customer was ever onboarded” -
      which survives the next minted one. Verified in the browser with a regex for a
      count-shaped claim rather than by re-reading the sentence I had just written.)
- [x] Verified in a browser on both pages, in both states, rather than by reading the source.
      (Four states: `demo-shop1` shared and minted, `demo-shop2` shared and minted, against the
      real built bundle served locally. It earned its place immediately - the safety card's
      privacy paragraph was still telling a minted visitor that any stranger could read their
      conversation, and no amount of reading the diff would have shown that, because each of the
      three blocks looked correct on its own.)

## Open questions

**Whether the widget should say anything at all on a minted tenant.** Silence is defensible: the
panel already said it. But the widget is the surface a visitor is actually looking at while typing,
and `8-06`'s original argument — that the warning belongs where the typing happens — applies just as
well to the reassurance.

## What shipped

### The open question, answered: the widget says something

`8-06` argued the warning belongs where the typing happens, because the launcher floats over every
scroll position and a visitor can open the panel without having read the page. **That argument does
not care which way the fact points** — the reassurance belongs there for the same reason, and the
tenant's own lifetime was stated nowhere in the widget at all. Silence would also have left the panel
visually identical in the two cases, so a reviewer comparing them could not tell the notice had become
conditional rather than simply deleted.

> This is your own demo tenant. Only the operator login you were given can read this conversation, and
> the tenant deletes itself after about a day.

**Precise rather than generous, and deliberately not the panel's wording.** `8-09`'s panel says
"Nobody else can see its conversations", which over-claims: the visitor holds a `?site=` link and a
password and can pass either on. The widget states what the deployment actually enforces. And there is
no "do not type anything real" — on a public tenant that is proportionate; here it would re-create the
contradiction this item exists to remove, in a softer form. The disposability says the true version of
the same caution.

### How the notice follows the tenant

`data-public-demo` (boolean) became `data-demo-notice` (`"public" | "private" | "none"`). Two booleans
would have admitted a fourth combination meaning nothing. `data-public-demo="true"` is **still honoured
as an alias** — the bundle is a public script tag on a public URL, somebody may have copied the demo
page's markup, and `api-design.md`'s reasoning about an embed that "cannot be forced to upgrade"
applies to a script tag's attributes as much as to a route.

An unrecognised value falls through to **silence**, never to a guess: defaulting to `"public"` would
put a false warning on a private tenant and defaulting to `"private"` would remove a true one from a
public page, so the only default that cannot mislead somebody is saying nothing.

### How the safety card argues its point now

It used to argue from a count. It now argues from what is actually true and stays true: every tenant on
this deployment is a demo tenant — the seeded shops plus the throwaway ones the button mints — and no
real customer has ever been onboarded, so there is no production data behind any login on this server.

### Also stale, found while there

- **The top banner**, on a minted `?site=` page — the same contradiction one layer up, and squarely
  inside the first Done-when. Swapped by `demo-boot.js` from the same decision as the widget's.
- **The safety card's privacy paragraph** — the third instance, found only in the browser.
- **Both operator-login cards** said "this tenant" / "this dedicated demo tenant", which on a minted
  page points at the visitor's own tenant, which those credentials cannot reach at all. Now named:
  "Operator login for Demo Shop One/Two", and each says explicitly that it never reaches a minted
  tenant — which turns a stale phrase into a statement of the isolation a reviewer came to check.
- **A comment defending the bug**, at the bottom of both pages: "the page stays public even when the
  tenant is private, and that notice is still the honest thing to show". Replaced with why that is
  half-true and why it does not license the sentence it was defending.

**`ago-landing` needed no change** — checked, both languages. `8-09` already updated it, and it
describes the mint button correctly ("a private operator account nobody else can see into, for about a
day") and never mirrors the tenant-count claim.
