# The login page is the one screen `11-05` did not reach

- **Stage**: 11 — added 2026-08-25, after the stage's other items had shipped. Stage 11 is a name
  rather than a schedule (`roadmap.md`'s "What comes next"), and this belongs to the stage that owns
  how both surfaces look, not to whichever one happens to be open.
- **Status**: ready
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

- [ ] A login theme exists, extends the stock parent, and is delivered by a committed mechanism rather
      than a manual copy into a running container.
- [ ] `loginTheme` is set in the realm import and survives a re-import.
- [ ] Sign-in, registration, password reset, email verification and at least one error page all carry
      the identity, verified on the real deployment.
- [ ] The tokens are traceably `11-05`'s, with a stated mechanism that prevents divergence rather than
      a promise to keep them in step.
- [ ] The webfont decision is recorded, in `adr/0030` if it changes anything that ADR said.
- [ ] Whatever delivery mechanism is chosen is confirmed to work in whichever Keycloak mode `15-01`
      settles on — or, if that item has not landed yet, the interaction is written down rather than
      discovered later.

## Open questions

None. The webfont choice is a real decision, and it is this item's own to make and record.
