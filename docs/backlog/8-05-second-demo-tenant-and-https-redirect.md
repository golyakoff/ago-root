# A second, independent demo tenant, and the permanent HTTP→HTTPS redirect

- **Stage**: 8
- **Status**: done
- **Depends on**: `8-02-public-demo-page-and-console.md` — needs the first demo tenant, its
  static-bundle image mechanism, and the live console already working

## Goal

Two visibly different public demo shops, each its own tenant, each its own operator login, so a
reviewer can watch tenant isolation work live instead of taking it on faith from the code alone: log
into `demo-shop1`'s operator, log into `demo-shop2`'s operator (a second browser/incognito window —
the console's session is a cookie, one identity per browser context), and see that neither can reach
the other's conversations. Also closes a gap `8-01` deliberately left open: every `*.reserve-me.ru`
origin now redirects plain HTTP to HTTPS, not just the hostnames that happen to be TLS-terminated.

## Context to read first

`backlog/8-02-public-demo-page-and-console.md` — the mechanism this item's second tenant reuses
unchanged (build-time `AGO_API_BASE_URL`, per-site CORS, Keycloak client registration); this item
adds a second *site*, not a second mechanism. `ago-deploy/seed/create-demo-tenant.sh`'s own comments
on `SITE_ID`/`OPERATOR_ID` — the fixed-id pattern this item's second tenant follows exactly, under
its own fixed ids. `k8s/overlays/demo/gateway.yaml`'s original `http` listener comment (before this
item) — explicitly deferred the redirect "for lack of a live server to verify it against."

## Scope

- A second demo page (`ago-widget/public-demo-2/index.html`) — same widget bundle, a visually
  distinct (dark theme) page, `data-site="demo_site2"`, its own operator credential shown in the page
  itself, matching `8-02`'s own "state the credential on the page" rule.
- `ago-widget/Dockerfile`'s new `DEMO_PAGE_DIR` build arg so one Dockerfile produces either tenant's
  image (default unchanged, `public-demo`, for `demo-shop1`).
- `ago-deploy`: `demo-shop2-static.yaml` (Deployment+Service, same shape as `demo-shop1-static.yaml`),
  a new Gateway listener+HTTPRoute for `demo-shop2.reserve-me.ru`, the hostname added to the TLS
  Certificate's SANs, `build-static-images.sh` extended to build the third image.
- A second, fully independent site/operator/role seeded in Postgres (own fixed ids, own
  `external_subject_id`) and a second Keycloak user (`demo-operator-2`) — `seed/create-demo-tenant.sh`
  and `k8s/base/keycloak-realm-import.json` both updated so a fresh install reproduces this too, not
  only the live deployment.
- The permanent HTTP→HTTPS redirect: a `RequestRedirect` HTTPRoute filter on the `:80` listener,
  wildcard-hosted (`*.reserve-me.ru`), left un-special-cased against cert-manager's own ACME HTTP-01
  solver route — Gateway API's own route-precedence rules (exact hostname beats wildcard, exact path
  beats `PathPrefix`) mean the solver's route always wins for its own request without this route
  needing to know about it.

## Out of scope

- A second Keycloak realm or a second `ago-console` client registration — both tenants share the one
  `ago-chat` realm and the one `ago-console` OIDC client; isolation is enforced entirely by
  `roles.site_id` scoping (`5-01`, `5-05`), the same mechanism that already isolates any two sites.
- Automated cross-browser isolation testing — verified by hand for this item (two real logins, two
  real tokens, checked against `/api/v1/operators/me`), not a new automated test suite.
- A third demo tenant, or making tenant creation self-service — `10-*`'s own scope, unrelated to
  proving isolation with two fixed, seeded examples.

## Done when

- [x] `https://demo-shop2.reserve-me.ru` loads, the widget connects, and a real message sent from it
      lands in Postgres tagged with `demo_site2` — verified live.
- [x] `demo-operator-2`/`demo-operator-2-password` logs in (direct grant, real token) and resolves via
      `/api/v1/operators/me` to `siteId=...0008` — a different site than `demo-operator`'s `...0001` —
      confirmed live, not asserted from the seed SQL alone.
- [x] `http://` on any `*.reserve-me.ru` hostname returns a real `301` to the `https://` equivalent,
      verified live; the TLS certificate re-issued in place with the new SAN with no downtime to the
      other five hostnames.

## Found live while building this

**Keycloak's declarative User Profile silently rejected a `lastName` containing parentheses.** The
first `demo-operator-2` attempt used `"lastName": "Operator (tenant 2)"` — the user was created
successfully (id, username, email, `requiredActions: []` all correct in the Admin API's own
representation), but every direct-grant login attempt failed with `invalid_grant: "Account is not
fully set up"`, no further detail, and the user's `requiredActions` list stayed empty even after the
failure — nothing in the API response pointed at the cause. Root cause, found by comparing the
working `demo-operator` user's representation field-by-field against the broken one (identical except
`lastName`) and then testing the one difference: Keycloak's realm-level User Profile validation
rejects that value's shape at *login* time (triggering an internal `VERIFY_PROFILE` check the direct
grant flow cannot satisfy interactively), not at creation time — the Admin API happily accepts and
stores a `lastName` it will later refuse to let the user log in with. Fixed by using a plain
`"Operator2"` instead; `k8s/base/keycloak-realm-import.json` updated to match so a fresh install
never hits this. Worth remembering for any future seeded user: keep `firstName`/`lastName` to plain
alphanumeric text, since Keycloak's own validation error here gives no actionable signal.

**`--import-realm` on Keycloak's *next* restart does add a new user to an already-provisioned realm** —
correcting an assumption `8-02`'s own runbook step 12 stated as fact ("Keycloak's import step is
skip-if-exists, not upsert-on-boot", generalized from `local-dev.md`'s finding for a *fresh* install).
Live evidence here says otherwise for at least the *new-entity* case: editing
`keycloak-realm-import.json` to add `demo-operator-2` and then restarting the pod (`kubectl apply`
picking up the changed ConfigMap) produced a real, working user with the exact fixed id from the
JSON, before this session ever called the Admin API successfully (a first Admin API attempt failed
with `401`; by the time a working token was used, the user already existed with a `409 Conflict`).
Whether an *update* to an already-existing entity behaves the same way remains untested — treat that
specific case as still open, but "adding a brand-new user via the committed JSON plus a rollout
restart works against a live realm" is now a confirmed fact, not the open question `public-deploy.md`
previously left it as.

## Open questions

None for this item's own scope. The Keycloak upsert-on-restart behavior noted above is confirmed for
new entities but not for updates to existing ones — left as a note for whichever future item needs to
change an already-provisioned user or client, not a blocker here.
