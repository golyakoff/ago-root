# The login page is the one screen `11-05` did not reach

- **Stage**: 11 — added 2026-08-25, after the stage's other items had shipped. Stage 11 is a name
  rather than a schedule (`roadmap.md`'s "What comes next"), and this belongs to the stage that owns
  how both surfaces look, not to whichever one happens to be open.
- **Status**: done — 2026-08-26, with one done-when box deliberately left open (below). Shipped in two
  passes: `ago-deploy` `fbda4cd` built the theme and put it on the live demo, and named one thing it
  owed; a second pass paid that debt and verified the pages the first could not. What each did is in
  "What shipped" below, including what is still open.
- **Depends on**: `11-05-console-design-foundation.md` (shipped) — this item consumes its tokens and
  must not restate their values; and nothing else

## Goal

An operator's first screen stops being a stranger's. Today the path is: the marketing page in Manrope
and Unbounded, then Keycloak's stock login theme with no AGO identity of any kind — "Sign in to
ago-chat" in the default Red Hat styling — and only then a console that was deliberately designed.
Nobody chose the middle screen; it is what the upstream image ships. After this item, the login,
registration and password-reset pages are recognisably the same product as the two screens either
side of them.

## Why this is worth doing at all

Stated plainly, because "restyle the login page" is exactly the kind of item that sounds like polish.
It is the screen that carries the first impression of the product for every operator and every
self-registered account holder (`10-01`), and it is the *only* screen in the whole flow that says
nothing about who made it. `11-05` argued that a designed console matters because a reviewer opening
the demo sees it first — the login page is what they actually see first, and it was missed because it
lives in a different repository and belongs to a component nobody thought of as "ours".

## Context to read first

`ago-console/src/design/tokens.css` — the single source of every colour, radius, shadow and type
size, and the file this theme must read rather than re-declare. Its own header explains which values
were carried over from `ago-landing` unchanged and which were recomputed for working density, and the
same distinction applies here: a login page is a moment, not a shift, so it sits closer to the
landing page's proportions than the console's. `adr/0030` — the design-system decision, including the
Google Fonts trade-off this item has to look at again in a different context (below).
`ago-deploy/k8s/base/keycloak.yaml` — the upstream `quay.io/keycloak/keycloak:26.0` image with
exactly one volume mounted, the realm-import ConfigMap; that is the whole current surface, and this
item adds to it. `ago-deploy/k8s/base/keycloak-realm-import.json` — sets no `loginTheme`, so the
default applies. `docs/backlog/15-01-keycloak-persistent-user-store.md` — its `start-dev`-versus-`start`
decision interacts with this item, since theme caching is disabled in the first and enabled in the
second.

## Scope

- **A login theme that extends Keycloak's own rather than replacing it.** A `theme.properties` naming
  `keycloak` as parent plus a stylesheet is enough to restyle the pages; overriding FreeMarker
  templates is not, and each template overridden is one more thing that breaks on a Keycloak upgrade.
  Stay in CSS unless a specific page genuinely cannot be reached that way, and say which and why if so.
- **The tokens come from `11-05`, not from taste.** Copying the values into a second file makes a
  second source of truth that will drift — the failure this project has already fixed twice
  elsewhere. Decide how they get there (generated at build time from `tokens.css`, or vendored with a
  check that fails when they diverge) and state the choice; "we copied them carefully" is not one.
- **Every page in the flow, not just the login form**: sign-in, registration (`10-01`), password reset
  and email verification (`10-05` makes both reachable for the first time), plus the error and info
  pages people land on when something goes wrong — those are the ones seen at the worst moment and
  the ones invariably left stock.
- **Decide how the theme reaches the container.** A ConfigMap mounted at `/opt/keycloak/themes/<name>`
  is the smallest change and fits a CSS-only theme; a derived image is more machinery but survives
  growing past what a ConfigMap should carry. Pick one, state the reasoning, and note that whichever
  is chosen must keep working when `15-01` decides the `start-dev`-versus-`start` question, since
  production mode caches themes and dev mode does not.
- **Set `loginTheme` in the realm import** so the choice survives a re-import rather than living in an
  admin console nobody re-clicks.
- **Look at the font question again, in this context.** The console fetches Manrope and Unbounded from
  Google Fonts, a trade-off `adr/0030` weighed for a dashboard. A login page is not a dashboard: it is
  the one page in the product where a third-party request sits next to a password field. Self-hosting
  the two faces in the theme, or falling back to the system stack the tokens already end in, are both
  real answers. Decide deliberately — this is the one genuine decision in the item, and it may deserve
  a line in `adr/0030` rather than a silent choice here.
- **Verified live on the real deployment**, on the actual pages, including at least one error state —
  not by screenshotting a local Keycloak with a happy path.

## Out of scope

- Keycloak's account console and admin console. Different audiences: the account console is barely
  used in this product (operators are managed by the tenant, not self-service) and the admin console
  is the author's own tool. If the account console ever becomes part of the product, it gets its own
  item and reuses this one's stylesheet.
- Translating any of it — `vision.md` still lists interface i18n as out of scope, and Keycloak's own
  message bundles are where that would happen if it ever changes.
- The emails Keycloak sends (`10-05`'s territory once there is a sender at all). They have their own
  theme type, and styling a message nobody can send yet would be building on air. Name it there when
  it lands.
- Anything about the console itself — `11-05` and `11-06` shipped and this item does not revisit them.
- Changing Keycloak's authentication flows, forms or fields. This is appearance only; `17-06` owns the
  realm's login *behaviour*, and the two should not be confused because they touch the same screens.

## Done when

- [x] A login theme exists, extends the stock parent, and is delivered by a committed mechanism rather
      than a manual copy into a running container.
- [x] `loginTheme` is set in the realm import and survives a re-import.
- [ ] Sign-in, registration, password reset, email verification and at least one error page all carry
      the identity, verified on the real deployment. **Partly.** All five (eight, in fact) are verified
      — but only sign-in and registration were checked *on the demo*, by the first pass. The other six
      were driven and measured on a local Keycloak running the same mounted files, because the second
      pass was explicitly barred from touching the live cluster while `17-05`'s hardening was in
      flight. Since the theme is static files plus one realm field, and both targets mount the same
      two files, the gap is small — but it is a gap, and this box stays open until someone walks the
      remaining six pages on the demo. Left unticked rather than argued away.
- [x] The tokens are traceably `11-05`'s, with a stated mechanism that prevents divergence rather than
      a promise to keep them in step.
- [x] The webfont decision is recorded, in `adr/0030` if it changes anything that ADR said.
- [x] Whatever delivery mechanism is chosen is confirmed to work in whichever Keycloak mode `15-01`
      settles on — or, if that item has not landed yet, the interaction is written down rather than
      discovered later.

## What shipped

**The theme.** `ago-deploy/k8s/base/keycloak-theme/` — a `theme.properties` naming `keycloak` as the
parent and one stylesheet appended after the parent's, and **not one FreeMarker template overridden**.
Delivered as a ConfigMap (`kustomization.yaml`'s `configMapGenerator`) mounted at
`/opt/keycloak/themes/ago/login`, because the whole theme is two text files; that stops being true the
day it carries a font or an image, and a derived image is the answer then.

**How the tokens get there, and what catches drift.** The values are *vendored* — a container that
mounts a ConfigMap has no `ago-console` to `@import` from — but the copy is machine-made and
machine-checked. `k8s/check-theme-tokens.sh` reads `ago-console/src/design/tokens.css`, collects the
tokens the stylesheet actually references, rebuilds the block between `GEN-BEGIN`/`GEN-END`, and exits
non-zero on any difference; `--write` regenerates it. `redeploy.sh` runs the check straight after it
pulls both checkouts. Four kinds of drift were provoked and all four failed the check: a changed value
in `tokens.css`, a hand-edit of the generated block, a `var(--ago-…)` naming a token `tokens.css` does
not declare, and a change to the console's system font fallbacks. The one deliberate divergence — the
login page loads no webfont — has its own name (`--ago-login-font`) and its own assertion: it must be
a *suffix* of the console's `--ago-font-sans`.

`ago-deploy` has no CI, so outside a redeploy this check runs when a person runs it. That is the
honest limit of the mechanism and it is written into the script's own header.

**The webfont decision, recorded in `adr/0030`'s 2026-08-26 amendment.** No webfont on these pages.
Measured, not asserted: driven through headless Chrome over CDP, the sign-in page issues eleven
requests and **every one is same-origin** — including the only `.woff2` on the page, which is the
FontAwesome file the upstream image serves itself. There is no font host to be unreachable, which is a
different and better answer than "it degrades gracefully".

## Verification

Eight pages, driven end to end against a Keycloak container running the mounted theme, then measured
with `getComputedStyle` over CDP — the values the browser actually resolved, with `var()` substituted:
sign-in, sign-in with a bad password, registration, registration with field errors, email
verification, forgot-password, the info page after submitting it, and the `Client not found` error
page. All eight linked `login/ago/css/ago.css` after the parent's own sheet and computed
`background #fbfaf7`, card `#ffffff` at `16px`, submit `#4b3aff` at `12px`, inputs `8px`, links
`#3324c9`, labels `#57546f` at `13px` — every one a `tokens.css` value. Registration's inline errors
computed `#9f1d17` on both the message text and the invalid field's border. The flow was real rather
than mocked: registering sent an actual "Verify email" message and forgot-password an actual "Reset
password" one, both caught in a local Mailpit.

**Degraded states, observed rather than reasoned about.**

- **Theme absent, `loginTheme` still set.** Keycloak logs `ERROR … Failed to find LOGIN theme ago,
  using built-in themes`, returns `200`, and serves a fully working login page — in **Keycloak 26's
  own default theme, `keycloak.v2`**, not in the `keycloak` theme this one extends. So a missing theme
  is a visible-but-safe failure, and the fallback is a *different* stock theme from our parent.
- **`theme.properties` present, `ago.css` missing** (a ConfigMap that lost a key). The theme loads,
  the parent's styling applies, the page still links `ago.css`, and that request **404s in silence** —
  nothing in Keycloak's log at all. This is the quiet one: the login page reverts to stock and no
  signal is emitted anywhere.
- **A font host being unreachable** has no effect, because there is no third-party request to fail.

**The parent is the older markup family, and that was measured too.** `parent=keycloak` is PatternFly
v3; Keycloak 26.0's own default is `keycloak.v2` (PatternFly v5) — which is what the fallback above
proves. The same `ago.css` was mounted onto a second Keycloak with `parent=keycloak.v2` and
`styles=css/styles.css css/ago.css`: the sign-in page computed **identical values on both parents**.
That is what the doubled `pf-c-*`/`pf-v5-c-*` selectors buy — switching parents is a two-line change,
not a rewrite. It is left on `keycloak` because that is the parent all eight pages were verified on,
and the finding is recorded in `theme.properties` itself rather than in a commit message.

## What anyone changing this theme later needs to know

- **`start-dev` does not cache themes; `start` does** — and this matters less than it looks, which is
  worth saying rather than leaving as a trap for the reader. The demo runs `start-dev` (`adr/0022`,
  kept deliberately by `adr/0036`), so in the compose loop the bind-mounted stylesheet is re-read on
  the next request and an edit is live immediately. Under Kubernetes the theme is a
  `configMapGenerator` output whose name carries a content hash, so editing `ago.css` changes the
  ConfigMap's name, changes the Deployment's pod spec and rolls the pod — the new theme is live after
  `kubectl apply -k` whichever mode Keycloak is in. `15-01`'s deferred `start --optimized` work
  therefore does not break the delivery mechanism; it only removes the compose loop's edit-and-reload
  convenience, and it makes editing a file inside a running container (never the procedure anyway)
  useless rather than merely wrong.
- **`--import-realm` is skip-if-exists, so a changed `loginTheme` does not reach an existing realm.**
  It reaches a fresh cluster (verified: a container booted against an empty database imported the
  realm and served the theme). For a realm that already exists the mechanism already exists too —
  `k8s/apply-realm-settings.sh` PUTs the file's realm-level fields, and `loginTheme` is one of them.
  Checked by setting `loginTheme` to something else on a running realm and running exactly that
  update: it came back to `ago`, with users untouched. `kc.sh import --override true` would also work
  and would take every self-registered account with it; it is never the answer here.
- **The local compose loop mounts the theme** (`docker-compose.yml`). Before that it did not, while
  the realm import it shares already carried `loginTheme: ago` — so the local loop was hitting the
  first degraded state above and showing a stock login page that looked nothing like the cluster's.

## Open questions

None. The webfont choice was this item's own to make; it is made and recorded in `adr/0030`.

Two things are named rather than done, both deliberately:

- **The parent stays on the older PatternFly v3 theme.** Measured as a two-line switch, not verified
  across all eight pages on the new parent, and not worth a visible change to a live product screen
  inside an item scoped to appearance.
- **The account console is still stock** — out of scope above, and unchanged.
