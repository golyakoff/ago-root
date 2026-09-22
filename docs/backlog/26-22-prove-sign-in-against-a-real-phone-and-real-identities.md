# 26-22 · Prove sign-in against a real phone and real identities

- **Stage**: 26
- **Status**: ready — blocked on a real physical device and two real test identities, not on design
  or code
- **Found**: 2026-09-22, carrying out `26-12`'s own remainder. `26-12` shipped and unit-tested the
  entire sign-in/routing/tenancy mechanism (the OIDC handshake against the live realm, the four-arm
  routing tree, token refresh, the `X-Ago-Active-Site` plugin) and left three Done-when boxes
  genuinely unsettled for the reason its own report states plainly: no physical Android device and no
  real operator/platform-owner test identity were available in that worktree. This is that remainder,
  given its own number per this project's own rule rather than left as an open box under a closed
  item.
- **Depends on**: a physical Android phone, and two disposable test identities in the live `ago-chat`
  Keycloak realm — one a real operator (a seat at a real site), one holding the `platform-owner` realm
  role and no `operators` row. Neither exists yet. `26-11`'s own outcome is the precedent for creating
  and deleting a disposable Keycloak user via `kcadm` for a proof like this one.

## What this item is

`26-12`'s own hand-off names the exact manual steps; this item is running them for real and recording
what happened.

## Scope

1. **A real operator, on a real phone.** Create a disposable operator identity (a real `operators` row
   at a real site — redeem an invite through the console, or `kcadm`-created plus a direct database
   row, whichever this project's own conventions prefer for a throwaway test account). Install `26-09`'s
   own published debug APK on a physical Android phone, sign in, confirm the "Вход выполнен" placeholder
   names the right site. Delete the identity afterward.
2. **The owner and registration arms, against real identities.** Sign in as an identity holding
   `platform-owner` and no `operators` row — expect the terminal screen with the web-console link.
   Sign in as a fresh, tenant-less identity — expect the registration arm's own message. (The author's
   own account holds both an operator seat and the owner role, so it cannot exercise either arm alone —
   `12-03`'s own history is why this bug survived unnoticed as long as it did.)
3. **Token refresh against the real API.** Sign in, wait past the realm's real access-token lifetime
   (or force an early expiry if the realm's admin console allows it), make a call, confirm no sign-in
   prompt appears and the call succeeds.
4. **Logcat with a real token present.** During steps 1–3, run `adb logcat -b all -v long | grep -iE
   "Bearer|access_token|refresh_token|eyJ"` and confirm nothing matches — `26-12`'s own proof covered
   only the no-token OIDC-discovery run, not a session actually holding one.
5. **The multi-tenancy arm**, if convenient to set up alongside step 1: give one identity operator rows
   at two real sites, confirm the site picker appears before anything else, confirmed against a real
   phone rather than only `PostSignInRouterTest`'s own fake port.

## Out of scope

- Any code change, unless one of these proofs finds a real defect — in which case that defect gets its
  own item per this project's own rule, not a fix folded quietly into this one.
- `26-05`/`26-21`'s own real-send proof — a different real-world precondition (a RuStore project),
  unrelated to this item's own (a phone and two identities).

## Done when

- [ ] A real operator signs in on a real phone against the live API and reaches the placeholder
      "signed in" surface, naming the right site.
- [ ] An owner-only identity reaches the terminal screen; a tenant-less identity reaches the
      registration arm — both against real identities on a real phone.
- [ ] An expired access token is refreshed and the retried call succeeds with no sign-in prompt,
      against the real API.
- [ ] A live `adb logcat` sweep with a real token present shows no `Bearer`/token/JWT-shaped string.
- [ ] Every disposable test identity created for this item is deleted afterward, confirmed.
