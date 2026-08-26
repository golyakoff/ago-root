# The half of demo credentials a stranger can actually see

- **Stage**: 8
- **Status**: ready
- **Depends on**: `8-07` — merged, and it built everything behind this. Nothing here is a redesign;
  `adr/0058` already decided the shape and named this gap as its own Consequence.

## Goal

A stranger who has never met the author opens the demo, presses one thing, and is looking at their
own operator console with their own conversation in it. Today `8-07`'s endpoint can produce exactly
that — and no page calls it.

## Why this is a separate item rather than an oversight

`8-07` chose a **tenant per viewer** over joining the shared demo site, because joining the shared
site fixes only *identity* and leaves every viewer reading every other viewer's conversations, which
is the main thing the item existed to fix. That choice is right and it has a price, stated in
`adr/0058` rather than discovered later: **the public demo pages boot a baked-in site key.** A minted
viewer therefore gets a console of their own with no widget pointing at it.

That is **worse than the shared account it replaces**, not merely incomplete — which is why
`8-07`'s own feature flag is shipped **off in the demo overlay**, and why enabling it is this item's
last step rather than its first. Until then the deployment behaves exactly as it did before.

## Scope

- **`ago-widget`'s two `public-demo*/index.html` pages read `?site=`**, falling back to the baked-in
  key when it is absent so the pages keep working for everyone who arrives without one. This is the
  load-bearing change; everything else here is affordance.
- **A button.** "Try the console with your own tenant" — wherever a stranger actually lands, which is
  a real decision this item makes: `ago-landing`, the demo shop pages, or both. It calls `8-07`'s
  endpoint and shows the returned credentials **on screen**, plus the `visitorUrl` that carries the
  new tenant's own key.
- **The credentials must survive being looked away from.** A stranger will open the console in a
  second browser context (the existing README already tells them to) and needs to type the password
  there. Show it in a form that can be copied, and say plainly that it disappears on reload and
  cannot be recovered — because it cannot.
- **Say it is temporary and roughly how long it lasts**, in the UI, not only in the API response.
  `8-07` makes everything minted recognisably temporary in the data; a viewer should learn it from
  the page rather than from a name.
- **The rate limit and the cap are visible outcomes, not stack traces.** `429` and "the demo is at
  capacity, try again shortly" are both ordinary states here, and both are reachable by a stranger on
  a busy day.
- **Last step: flip `DemoTenant__Enabled` to `true`** in `k8s/overlays/demo/kustomization.yaml` and
  deploy. The comment there points at this item.

## Out of scope

- Any change to `8-07`'s endpoint, its cap, its rate limits or its expiry sweep. If this item finds
  something wrong with them, **report it rather than fixing it here** — the two halves should not
  move together without a reason.
- `8-06`'s shared-page notice. It stays useful: the demo *pages* remain shared even once every viewer
  has their own console.
- Real-customer signup (Stage 10). This is a demo affordance and must not grow into a second
  registration path.

## Done when

- [ ] A stranger obtains working credentials with nobody intervening — the Done-when `8-07` left
      unticked, and it belongs here.
- [ ] Two people doing this at the same time, **in two real browsers**, are two operators who cannot
      see each other's conversations — the other one `8-07` left unticked. Proven end to end against
      a running stack, not as a property of two API calls.
- [ ] A demo page opened with `?site=` talks to the tenant that link belongs to, and the same page
      opened without one still works exactly as it does today.
- [ ] Hitting the cap and hitting the rate limit each produce something a person can read.
- [ ] The flag is on in the demo overlay, and the live demo does the whole walk.

## Open questions

**Where the button lives**, which is a product question rather than a technical one: the landing page
is where a reviewer arrives, the demo shop pages are where somebody who is already curious is
standing. Both is defensible and costs two implementations of the same call.

**What happens to the shared `demo-operator` account afterwards.** `8-07` deliberately left the
seeded `8-05` tenants alone, and they are what demonstrates tenant isolation live. But the README
currently hands strangers those shared credentials, and once this lands it should probably hand them
a button instead. Decide, and update the README in the same change if the answer is yes.
