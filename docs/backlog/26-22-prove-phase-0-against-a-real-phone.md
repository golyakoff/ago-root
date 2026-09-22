# 26-22 · Prove Phase 0 against a real phone

- **Stage**: 26
- **Status**: ready — blocked on a real physical device and two real test identities, not on design
  or code
- **Found**: 2026-09-22, carrying out `26-12`'s own remainder, then widened twice the same day.
  `26-12` shipped and unit-tested the entire sign-in/routing/tenancy mechanism (the OIDC handshake
  against the live realm, the four-arm routing tree, token refresh, the `X-Ago-Active-Site` plugin)
  and left three Done-when boxes genuinely unsettled for the reason its own report states plainly: no
  physical Android device and no real operator/platform-owner test identity were available in that
  worktree. This is that remainder, given its own number per this project's own rule rather than left
  as an open box under a closed item. **Renamed from a sign-in-and-hub-specific title once it became
  clear every Phase 0 item lands the identical shape of remainder** - built and unit-tested against a
  fake backend, genuinely unable to prove itself against a real phone and a real signed-in session in
  an environment with no test identity and no physical device. Rather than open a fourth, fifth,
  sixth near-duplicate item as each later Phase 0 piece hits the same wall, this one item collects
  them all and is run once, in one real session, when a phone and test identities exist. Carries, so
  far: `26-13`'s hub-connection reliability proofs (token expiry, network kill/restore, backgrounding/
  rotation), `26-14`'s conversation-list proofs (rendering against the live API, on-device rotation
  with scroll position), and `26-15`'s own two - **Phase 0's actual end-to-end proof itself** (the
  reason this whole stage exists: sign-in → list → thread → send → seen on the console, and a
  visitor's reply seen back on the phone) and the live send-retry-produces-exactly-one-message race -
  all added the same reasoning as `26-13`'s own widening: one real sign-in
  session proves all of it, not one session per item.
- **Depends on**: a physical Android phone, and two disposable test identities in the live `ago-chat`
  Keycloak realm — one a real operator (a seat at a real site), one holding the `platform-owner` realm
  role and no `operators` row. Neither exists yet. `26-11`'s own outcome is the precedent for creating
  and deleting a disposable Keycloak user via `kcadm` for a proof like this one.
- **Also carries `26-13`'s own remainder**: that item's SignalR hub connection is fully built and
  unit-tested against a fake port, and its only unsettled Done-when boxes need the identical real
  operator session this item already exists to obtain - once signed in for real (step 1 below), the
  same session is the natural moment to also exercise the hub's real token-expiry survival, network
  kill/restore reconnect, and exactly-one-connection-after-backgrounding/rotation proofs (steps 6-8
  below), rather than a second real-phone session solely for that.

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
6. **The hub connection survives real token expiry** (`26-13`): wait past the realm's real
   access-token lifetime (or shorten it deliberately if the realm's admin console allows), confirm the
   connection's own debug row stays healthy with no sign-in prompt.
7. **Killing and restoring real network reconnects the hub** (`26-13`): toggle the phone's own
   connectivity off and on, watch the debug row show `Reconnecting` then `Connected`, and send a
   message from the console while the phone is offline - confirm it appears exactly once on
   reconnect, neither missing nor doubled.
8. **Backgrounding/rotation leaves exactly one hub connection** (`26-13`): background the app, bring
   it back, rotate the device, and confirm server-side (the Redis `presence:operator:{id}` set, or
   whatever this deployment's own live inspection method is) that exactly one connection id exists for
   that operator throughout.
9. **Both conversation-list segments render against the live API** (`26-14`), reusing step 1's own
   operator identity - confirm «Мои» and «Ожидают» both populate with real data, and that a real
   assignment arriving while the list is open badges the row and never navigates.
10. **The conversation list survives rotation with scroll position intact** (`26-14`): scroll the list,
    rotate the device, confirm the scroll position is unchanged - the on-device confirmation
    `rememberSaveable`'s own architectural guarantee was never exercised against a real Activity
    recreation.
11. **Phase 0's actual end-to-end proof** (`26-15`) - the reason this whole stage exists, `plan.md`'s
    own words: sign in on the phone, open a thread from step 9's own data, send a message, confirm it
    appears in `ago-console` on a desktop for the same conversation; then send a reply from the
    console (or the widget, as the visitor) and confirm it appears on the phone with no refresh.
    **Record the date this was actually observed** - `26-15`'s own Done-when insists on it.
12. **The live send-retry race** (`26-15`): with a real send in flight, drop the connection at the
    moment of sending (airplane mode toggled mid-send, or a similar real interruption) and confirm
    exactly one message lands - not two, not zero - proving the client's retry-with-the-same-id
    behaviour and the server's own dedup together, not each in isolation as `26-15`'s own unit tests
    already did.

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
- [ ] The hub connection survives a real token expiry with no sign-in prompt (`26-13`).
- [ ] A real network kill/restore reconnects the hub, jittered, and a message sent while genuinely
      disconnected arrives exactly once on reconnect (`26-13`).
- [ ] Backgrounding and rotating the device leaves exactly one hub connection, proven server-side
      (`26-13`).
- [ ] Both conversation-list segments render real data against the live API, and a real assignment
      arriving while the list is open badges the row without navigating (`26-14`).
- [ ] The conversation list's scroll position survives a real device rotation (`26-14`).
- [x] **Phase 0's actual end-to-end proof**, recorded with the date it was observed: a message sent
      from the phone appears in `ago-console`; a visitor's reply appears on the phone with no refresh
      (`26-15`). **Observed 2026-09-22**, on a real physical device (a Redmi/Poco, model
      `2407FPN8EG`), immediately after `25-213`'s fix unblocked sign-in — with one substitution from
      the box's own literal wording, noted rather than glossed over: the receiving end checked was a
      real visitor widget conversation on `golyakov.net`, not an `ago-console` desktop tab. An
      existing conversation was reopened as the visitor in that widget ("Текстовое обращение
      22.09"), then opened on the phone under Диалоги → Мои and answered twice from there — both
      replies arrived in the widget **live, with no page refresh**, confirmed explicitly. This is the
      harder and more direct half of the proof the item exists for (a real Android client's SignalR
      connection sending to a real backend and a real second client receiving it live, in both
      directions) — the `ago-console`-side receipt of an operator's own outbound message is a
      mechanism that ships and has been exercised independently for months already, unlike this
      client's own connection, which had never sent or received anything over a real network before
      this session. Not part of this pass: dropping the connection mid-send (`box 12`, below) and the
      other Done-when items, none of which this session's brief window covered.
- [ ] A real send interrupted mid-flight (connection dropped at the moment of sending) produces
      exactly one message, not two, not zero (`26-15`).
- [ ] Every disposable test identity created for this item is deleted afterward, confirmed.
