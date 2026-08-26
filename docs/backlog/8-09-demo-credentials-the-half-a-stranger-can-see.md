# The half of demo credentials a stranger can actually see

- **Stage**: 8
- **Status**: **built, not deployed** (2026-08-26). Everything below is done except the deploy, which
  is deliberately left to a human — see the last Done-when.
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
      *Built and unit-tested, **not demonstrated**: it needs the flag on and a running stack, and this
      item stops before deploying. What exists: a button on both public demo pages that calls
      `POST /api/v1/demo/credentials` with no authentication and renders what comes back. Left unticked
      because "a stranger obtains" is a claim about a running system, and nobody has yet.*
- [ ] Two people doing this at the same time, **in two real browsers**, are two operators who cannot
      see each other's conversations.
      *Same reason. `8-07` already proves two mints are two tenants with nothing shared
      (`TwoMintsAreTwoTenantsWithNothingShared`, real Postgres, real Keycloak); what is still missing is
      the two browsers, which needs the deploy.*
- [x] A demo page opened with `?site=` talks to the tenant that link belongs to, and the same page
      opened without one still works exactly as it does today.
      *`resolveDemoSiteKey` (12 tests) plus `bootWidget` — the resolved key reaches the widget through
      the same `data-site` attribute it has always read. **The fallback is the half that mattered**: a
      page with no query string, or with a malformed one, boots its own baked-in key exactly as before,
      so every existing link is unaffected.*
- [x] Hitting the cap and hitting the rate limit each produce something a person can read.
      *`mint.ts` separates them from each other and from an ordinary failure — they clear differently
      (wait a moment vs wait for somebody else's tenant to expire), so they say different things.
      `panel.ts` renders both; six tests cover the two states and their wording.*
- [ ] The flag is on in the demo overlay, and the live demo does the whole walk.
      *Half done, and deliberately so. The flag **is** on in `overlays/demo` and both overlays render.
      The deploy is not done — see below.*

## Not done, on purpose

**The deploy.** Turning this on publishes an unauthenticated, tenant-creating endpoint on a public
URL. The manifest change is made and reviewed; running it is a separate, deliberate act. What to
expect when it happens is in the implementing session's report.

## Decisions this item made

- **The button lives on the two public demo shop pages, not on the landing page**, and
  `ago-landing`'s demo section points at it in both languages. The credentials have to appear where
  they can immediately be used: the `visitorUrl` a mint returns points back at a demo page carrying
  `?site=`, so the demo page is the only place the whole loop closes without a cross-origin hop. A
  landing-page button would have been a second implementation of the same call in a repository with no
  build step, for a worse loop.
- **The shared `demo-operator` logins stay in the README**, reframed rather than removed. A minted
  tenant proves *privacy*; the two seeded tenants prove *isolation* — one operator account that cannot
  see another's conversations — and those are different claims. Removing the seeded pair would have
  removed the live proof of the second. The README now leads with the button and keeps the table
  underneath, saying plainly that anything typed through a shared login is readable by anyone else
  using it.

## Open questions

**Where the button lives**, which is a product question rather than a technical one: the landing page
is where a reviewer arrives, the demo shop pages are where somebody who is already curious is
standing. Both is defensible and costs two implementations of the same call.

**What happens to the shared `demo-operator` account afterwards.** `8-07` deliberately left the
seeded `8-05` tenants alone, and they are what demonstrates tenant isolation live. But the README
currently hands strangers those shared credentials, and once this lands it should probably hand them
a button instead. Decide, and update the README in the same change if the answer is yes.
