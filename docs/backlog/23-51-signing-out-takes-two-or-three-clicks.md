# signing out takes two or three clicks, because the console signs itself back in first

- **Stage**: 23
- **Status**: ready
- **Found**: 2026-09-06, by the author, using the office console normally.
- **Decision**: none needed for the defect. One question about how far sign-out should reach is at
  the bottom, and it is the author's.

## The symptom

Press **Выйти** in the office console. Almost never works the first time. Sometimes twice, sometimes
three times, and only then does Keycloak's login page appear.

## The mechanism, read out of the code rather than guessed

`AuthProvider`'s `logout` is `userManager.signoutRedirect()`. Inside `oidc-client-ts`, `_signoutStart`
does this, in this order:

1. loads the stored user, to put its `id_token` in the request as `id_token_hint`;
2. **`await this.removeUser()`** — which fires the `userUnloaded` event;
3. navigates the browser to Keycloak's end-session endpoint.

Step 2 fires before step 3 completes. `AuthProvider` listens for `userUnloaded` and sets `user` to
`null`. And `RequireAuth` holds this:

```tsx
useEffect(() => {
  if (!isLoading && user === null) {
    login();          // userManager.signinRedirect()
  }
}, [isLoading, user, login]);
```

So **two navigations race**: the sign-out redirect that `signoutRedirect` is about to perform, and a
sign-*in* redirect that `RequireAuth` starts the instant the user disappears from the store.

When the sign-in wins, the browser goes to Keycloak's **authorize** endpoint instead. Keycloak's SSO
cookie is still valid — nothing has ended that session yet — so it redirects straight back, the
console signs in again, and from the operator's seat **the button did nothing**.

**That is why the count varies.** It is a race, not a fixed number of clicks: each press is a fresh
coin toss, and eventually sign-out wins.

## Why nothing caught it

Every test in this console mocks the user manager, so `removeUser`'s event ordering — the whole of the
defect — never happens. The `ux-gate` signs *in* and never signs out. And the symptom is
nondeterministic, so a single manual try looks like it worked.

## Scope

- **Stop the guard from racing the sign-out.** The signed-out state has to be distinguishable from
  *"not signed in yet"* while the redirect is in flight — a flag the sign-out sets before calling
  `signoutRedirect`, which `RequireAuth` respects, is the smallest shape. Whatever it is, it must
  survive the intervening render rather than living in a variable a re-render discards.
- **A test that fails on the current code.** It has to exercise the real ordering — `removeUser`
  firing `userUnloaded` before the navigation — because a mock that returns a resolved promise is
  exactly what hid this.
- **Check the other surfaces before assuming they are fine.** The calendar's screens are inside the
  same console since `22-06`, so they share this path; the demo shop pages have no sign-out at all;
  `/owner` uses the same `ShellIdentity` button.

## The question, which is the author's

**How far should sign-out reach?** Three readings, and the item deliberately picks none:

1. **End the Keycloak session only** — what is intended today. The operator is signed out everywhere
   that relies on that SSO session, including the calendar screens, because they are one console.
2. **Also clear this browser's own state deliberately** — `sessionStorage` holds the user, and
   `activeSiteStorage` holds the chosen tenant. Today the tab closing is what clears them. Whether a
   sign-out should also forget *which shop you were looking at* is a product choice, not a bug.
3. **Back-channel logout** — Keycloak can notify the application when a session ends elsewhere. That
   matters when one person has the console open in several tabs or devices; it is real work and is
   almost certainly not what this defect needs.

## Done when

- [ ] One press of Выйти reaches Keycloak's login page, every time.
- [ ] A test reproduces the race against the real event ordering and fails without the fix.
- [ ] Whether sign-out also clears the remembered tenant is decided and recorded.

## Out of scope

- Session length, token lifetime and silent renew. Those are `5-16`'s and working.
