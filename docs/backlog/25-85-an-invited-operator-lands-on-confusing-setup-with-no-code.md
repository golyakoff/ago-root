# 25-85 · An invited operator lands on confusing setup with no code

- **Stage**: 25
- **Status**: done, narrower than filed — `ago-chat#291`, `ago-console#232`. Independently re-verified
  by the managing session before merging (its own `dotnet build`/`test` and `npm` runs against the
  worker's own worktrees — 3331/3331 `ago-chat` tests, 1392/1392 `ago-console` tests, both matching the
  worker's reported counts exactly; the new redemption endpoint's claim-sourcing reviewed directly -
  email and subject come only from the authenticated JWT, never a client-supplied value). Three of
  four Done-when boxes are closed; the first stays open on purpose - see its own note - for the
  author's own live re-walk of the real flow, the same one that found this bug. Point 4 (the email's
  own fallback text) is carried to its own item, `25-90`, pending the author's decision on the
  plaintext-storage trade-off it names.
- **Depends on**: nothing
- **Found**: 2026-09-14, the author's own live walkthrough of `25-73`'s invite flow — sent a real
  invite, received the real email, followed the real link. Everything downstream of the click worked;
  what got in the way is what this item fixes.

## What actually happened

Clicking the invite email's link, completing Keycloak's own registration, landed the author on
`OnboardingPage` — titled **"Завершите настройку своего сайта"** ("Finish setting up your site"). For
someone who was invited to join an existing site as an operator, and never asked to set one up, that
framing is the wrong first sentence to read. The page does carry a small card noting a pending invite
exists, with an "activate it here" link (`strings.onboardingHasPendingInviteLink`,
`OnboardingPage.tsx`) — but that link is `<Link to="/redeem-invite">`, no query string at all, and
`RedeemInvitePage` shows an **empty** code field when it arrives with nothing to pre-fill. The author,
reasonably, read an empty required field as "type the code you were emailed" — except the code was
not at hand, so a colleague had to be asked to resend it and read it out.

**The code was never actually missing — it just never reached that link.** Two different paths land an
operator on `/redeem-invite` today, and only one of them carries the code:

- `CallbackPage.tsx` reads `?inviteCode=...` off Keycloak's own `redirect_uri` (set by
  `CreateOperatorInviteHandler`) and navigates to `/redeem-invite?code=...`, pre-filled — this path is
  built, tested, and evidently did not fire for the author's own walkthrough (or fired and handed off
  to the second path below before the code survived).
- `OnboardingPage`'s own "you have a pending invite" card links to `/redeem-invite` bare.
  `HasPendingOperatorInviteHandler` (`25-73`) deliberately returns only a `bool` - by design, per its
  own remarks, "nothing to authorize... a plain bool, no wrapping needed" - so this card's own
  read model never had the code to pass along in the first place.

## Scope

- **`OnboardingPage`'s pending-invite framing changes for an invited person specifically.** Someone who
  has a pending invite and no site of their own yet should not read "finish setting up **your** site" -
  the invite card's own message should lead, not sit as a small aside under a heading aimed at a
  different kind of visitor (someone self-registering to create a brand-new site). Read the page's own
  existing branching logic first; this may already partly exist and only need reordering.
- **The "activate it here" link carries the code.** `HasPendingOperatorInviteHandler`'s own design
  choice not to return the code (`25-73`) does not have to hold once the caller is genuinely
  authenticated: `RedeemOperatorInviteHandler`'s own remarks (`adr/0167`) already say redemption
  "checks the code and the authenticated caller's own email together" - the same dual check the
  Keycloak-redirect path's pre-filled code already relies on for its own security property. Widening
  (or adding a sibling to) that query, for an authenticated caller whose email matches the pending
  invite, to also return the code is not a new hole - it grants exactly the trust level the
  already-shipped `CallbackPage` path already grants, to a second path that currently grants less and
  is worse for it. State this reasoning explicitly in the change rather than silently widening a
  deliberately-narrow query.
- **The code is also placed as visible text in the invite email itself**, as a second, independent
  channel - "after creating your account, paste this into the invite-code field on [screen]." Not a
  substitute for either fix above; a redundant path for whenever an email client, a Keycloak redirect
  hop, or something neither fix above anticipated drops the automatic ones. Read `OperatorInviteEmailProvisioner`
  (`Ago.Chat.Infrastructure.Keycloak`) first - the email itself is Keycloak's own stock template
  (`execute-actions-email`, `adr/0167`), so this may need a custom email theme/template rather than a
  C# string change; say which it turns out to be.

## Where this is likely to go wrong

- **Find out why the Keycloak-redirect path didn't carry the code for this real walkthrough**, not
  only build the second, more-reliable path and call the investigation unnecessary. If `redirect_uri`'s
  query string is genuinely dropped somewhere in Keycloak's own registration/required-actions chain,
  that is worth naming precisely (and may affect other query-string-carrying redirects this codebase
  relies on) rather than quietly worked around.
- **Don't widen the pending-invite check for an unauthenticated caller.** The security reasoning above
  holds only once the caller is signed in and their own email is checked against the invite - an
  anonymous "does example@x.com have a pending invite, and if so what's the code" endpoint would be a
  real regression.

## Done when

- [ ] An invited operator's first screen after registering reads as "you're joining an existing
      site," not "set up your own," proven by walking the real flow (not asserted from the code).
      **Left open, honestly.** `OnboardingPage`'s heading now swaps to the invite framing whenever
      `hasPendingOperatorInvite` answers true, proven by a real component-level walk (`OnboardingPage.test.tsx`,
      "25-85: the invite framing leads for an invited reader" - renders the actual production
      component, asserts the actual rendered `<h1>` text, with a fails-before check confirmed by
      reverting the change and watching the new assertion fail). That is stronger than an assertion
      from reading the code, but it is not the literal live re-walk (a real invite, a real Keycloak
      registration, a real browser) the wording above asks for - a background worker has no way to
      perform that personally. Left unticked for the author's own live re-walk to close.
- [x] The "activate it here" link (or wherever it leads) arrives with the code pre-filled, for an
      authenticated caller whose email matches a pending invite - proven end to end, the same real
      walkthrough the author did tonight, this time without needing a resend.
      **"Pre-filled" became "redeemed directly, no code ever leaves the server"** - `HasPendingOperatorInviteHandler`
      turned out unable to return a code at all (`OperatorInvite.CodeHash` is a one-way hash, not a
      deliberately-withheld value - see the worker report). `RedeemInvitePage` now redeems automatically
      on arrival with no code, keyed by the caller's own authenticated email
      (`RedeemPendingOperatorInviteForCallerHandler`, `ago-chat`) - proven end to end against a real
      Postgres and a real Keycloak-signed token (`OperatorInviteEndpointTests.RedeemPendingForMe_*`,
      three tests: success, no-match refused, ambiguous-refused), and at the console layer by a real
      component walk (`RedeemInvitePage.test.tsx`, "25-85: redemption fires automatically..."). The
      security boundary - a caller whose email does *not* match gets nothing, never guesses, never
      redeems someone else's invite - is proven, not just the happy path.
- [x] Why the Keycloak-redirect path's own code did not reach this specific walkthrough is understood
      and stated, not left as "the second path exists now so it doesn't matter."
      **Root cause found and reproduced against a real Keycloak**: this realm has `verifyEmail: true`,
      and `OperatorInviteEmailProvisioner.CreateOrFindUserAsync` creates every operator-invite user with
      `emailVerified: false`. Keycloak's browser login flow appends a **third**, unrequested required
      action - `VERIFY_EMAIL` - to any authentication by such a user, regardless of the two actions
      (`UPDATE_PASSWORD`, `UPDATE_PROFILE`) this codebase actually asked for. The flow never reaches the
      OAuth redirect back to `redirect_uri` (carrying `?inviteCode=...`) at all - it stops on a "verify
      your email" holding page instead, which sends a **second**, unrelated email through Keycloak's own
      generic verify-email template, with no code and no `redirect_uri` context carried the same way.
      Reproduced end to end (`OperatorInviteRedirectQueryStringInvestigationTests`, `ago-chat`) by
      driving the standard Authorization Code flow through the identical `requiredActions`/`emailVerified`
      shape a real invitee gets, not the literal `execute-actions-email` action-token mechanism itself
      (that would need a real SMTP relay this suite's realm does not carry) - stated as the honest
      limit of this reproduction in the worker's own report, alongside why point 2's own fix does not
      depend on the answer either way (it never needed the redirect to carry anything).
- [ ] The invite email itself also carries the code as plain text, with instructions for where it
      goes - proven against whatever email templating mechanism turns out to be the real one
      (Keycloak's own theme, most likely).
      **Scoped down to its own item, `25-90`**, not built here. Keycloak's `execute-actions-email` Admin
      API takes no custom-template-variable parameter at all - the only real route is a custom email
      theme, and rendering the code inside it would need the plaintext code to reach Keycloak's own
      FreeMarker context somehow (most directly, a Keycloak user attribute), which is a real trade-off
      against `OperatorInvite`'s own "never stored in plaintext anywhere" design that the author should
      decide, not a worker. `25-90` names the two real paths and asks for that decision first.
