# 26-11 · A Keycloak realm client for the Android app

- **Stage**: 26
- **Status**: done — `ago-deploy#256`
- **Found**: 2026-09-21. `plan.md` §"Keycloak has exactly one public client, and the API validates a
  single audience" and `architecture.md` §Identity both name this as the one infrastructure chore
  standing between the approved plan and a native sign-in — and both name it as an **`ago-deploy`
  change and nothing else**. It had no number.
- **Verified**: 2026-09-21, read directly rather than taken from the plan:
  `ago-deploy/k8s/base/keycloak-realm-import.json` declares exactly two clients — `ago-console`
  (`publicClient: true`, `standardFlowEnabled`, redirect URIs `http://localhost:8080/*`,
  `http://localhost:5173/*` and the console's own web origin, carrying one protocol mapper
  `ago-console-audience` of type `oidc-audience-mapper` with `included.client.audience:
  "ago-console"`) and `ago-demo-provisioner` (`publicClient: false`, a service account, `8-07`).
  `ago-chat/src/Ago.Chat.Api/CompositionRoot.cs:295` reads
  `Auth:Keycloak:Audience` with a default of `"ago-console"`, and lines 326–327 set
  `ValidateAudience = true` / `ValidAudience = keycloakAudience` — a single string, not a list.
- **Depends on**: nothing. This can land before any Kotlin exists and is what unblocks `26-12`.

## What this item is

A native client can obtain a Keycloak token that `Ago.Chat.Api` already accepts — **with no change to
`ago-chat`**. One promise, provable by hand with a browser and `curl`, before the app exists.

## Scope

- **A new public client `ago-android`** in `keycloak-realm-import.json`: `standardFlowEnabled`, PKCE
  required (`pkce.code.challenge.method: S256`), a **native** redirect URI — a custom scheme or an
  https App Link; pick one, say which, and state why (AppAuth supports both and the choice has a
  real consequence for `26-12`'s deep links). No web origins it does not need, and no direct access
  grants.
- **An audience mapper copied from `ago-console-audience`'s own shape**, with
  `included.client.audience` set to the value `CompositionRoot.cs` already validates. This is the
  entire trick: the app presents a credential the resource server already knows how to accept.
  `plan.md` states the alternative — widening `ValidAudience` to a list — and why it is both forbidden
  by `26-00`'s Out of scope and the worse shape regardless.
- **The live realm, not only the file.** `--import-realm` is **skip-if-exists**
  (`docs/runbooks/realm-operations.md`): once a realm exists, the import file is never read again.
  `11-07` learned this with a `loginTheme` that did nothing, and `8-07` learned it with a client the
  import was expected to create and never did. So this item delivers **both** halves — the
  declaration, for a realm created fresh (`public-deploy.md`'s path), **and** an idempotent apply for
  the realm that already exists, in `apply-demo-provisioner.sh`'s own shape.
- **`docs/runbooks/realm-operations.md` gains the procedure in the same change** — it is the file that
  asks, in so many words, "what applies this to a realm that already exists?"

## Out of scope

- **Any change to `ago-chat`.** `26-00`'s Out of scope forbids it, and the audience mapper is exactly
  what makes it unnecessary.
- The app's own sign-in code (`26-12`).
- A second realm, a confidential client, or an Android-specific audience value.
- Anything touching the `ago-console` client — it keeps its redirect URIs, its mapper and its
  behaviour unchanged.

## Done when

- [x] An Authorization Code + PKCE exchange against the new client completes **by hand**, with no app:
      the authorize URL opened in a browser, the code captured from the redirect, the token exchanged
      with `curl`.
- [x] The decoded access token's `aud` contains exactly the value `CompositionRoot.cs` validates —
      checked against the decoded claim, not inferred from the mapper's configuration.
- [x] That token is accepted by `Ago.Chat.Api`: `GET /api/v1/operators/me` answers `200` or `403` and
      **never `401`** — the two acceptable answers both mean the token was validated.
- [x] Applying the client to a realm that **already exists** is proven on the demo realm, not assumed
      from the import file. Running the apply twice changes nothing the second time.
- [x] No secret, token, credential or node address appears in any committed file. The client is public
      and has no secret, which is part of why this shape was chosen.

## Outcome

Landed as `ago-deploy#256`. New public client `ago-android` in `keycloak-realm-import.json`:
`standardFlowEnabled`, PKCE required (S256), redirect URI `ago-android://callback` — a custom scheme
chosen over an HTTPS App Link because App Link verification needs a hosted `assetlinks.json` and the
app's own release-signing fingerprint, neither of which exist yet; PKCE is the standard mitigation for
a custom scheme's known weakness, and adding an App Link redirect URI later is additive. No secret, no
direct access grants. `ago-android-audience` mapper copied from `ago-console-audience`'s exact shape,
pointed at the same `"ago-console"` value `CompositionRoot.cs` already validates — no `ago-chat`
change of any kind. `k8s/apply-android-client.sh` (new) applies both idempotently to a realm that
already exists, following `apply-demo-provisioner.sh`'s established shape.

**Verified independently, live, against the real demo realm, before merging**: ran the apply script
twice (create, then a no-op confirming idempotency); completed a real Authorization Code + PKCE
exchange by hand (curl-driven — a disposable probe user created and deleted via `kcadm` for this one
test, never a real credential); decoded the resulting access token's `aud`: `["ago-console",
"account"]`; called `GET https://chat-api.reserve-me.ru/api/v1/operators/me` with it — `403
Forbidden`, never `401`, confirming the token was validated (403 rather than 200 because the probe
user holds no real `Operator` seat, exactly as expected). `docs/runbooks/realm-operations.md` gained
the procedure and a note on two real gotchas hit doing this the first time: the API's own hostname
(`chat-api.reserve-me.ru`) differs from the pattern a sibling service's hostname would suggest, and a
local sandbox's outbound HTTPS proxy can silently return a misleading `200 Connection established`
for a real domain — running the same commands over SSH on the node itself avoided the ambiguity.
