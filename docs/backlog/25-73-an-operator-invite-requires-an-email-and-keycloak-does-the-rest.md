# 25-73 · An operator invite requires an email, and Keycloak does the rest

- **Stage**: 25
- **Status**: code landed — `ago-chat#278`/`ago-console#218`, `adr/0167`. Not marked done: most of what
  this item promises depends on real Keycloak realm behavior (identity lookup, `execute-actions-email`,
  locale-aware templates, the SMTP error surfaced back) that could not be verified against a live
  realm — see *Shipped, and what still needs a real realm*, below — and one Done-when is met by a
  deliberate, stated deviation rather than as literally written.
- **Depends on**: `23-70` (link-based invite, done — this item removes the bare-code path it built),
  `23-27` (redeem-invite screen, done — this item removes the code-entry UX it built, replacing it with
  automatic redemption)
- **Found**: 2026-09-13. The author's own report: created an admin invite, copied the link, sent it via
  Telegram; the invitee had no account, landed on a login page, and — had they self-registered instead
  — would have created their **own** new tenant rather than joining the inviting site. Traced to a real,
  if narrow, gap: `23-27` already built a way out of that trap, but only as a small text link at the
  bottom of the generic "create your own company" form — easy for a hurried invitee to miss entirely.

## What is actually true today, verified 2026-09-13

- `CreateOperatorInviteHandler` (`POST /api/v1/sites/{siteId}/operator-invites`) takes no email at all —
  an invite is purely a code/link (`OperatorInvite.CodeHash`) the admin distributes themselves, however
  they like.
- `RedeemOperatorInviteHandler` (`POST /api/v1/operator-invites/redeem`) assumes a Keycloak
  session/account **already exists** — it does not and cannot create one.
- Self-registration (`RegisterSiteHandler`, `OnboardingPage.tsx`) is a genuinely separate path with no
  awareness of a pending invite — a self-registering invitee becomes owner of a brand-new site, exactly
  as reported.
- `23-27` already closed the "nowhere to enter the code" half: `/redeem-invite`, reachable from
  `/onboarding` via `pendingInviteCode.ts` (a code carried across the Keycloak login/registration round
  trip in `sessionStorage`) and a text link at the bottom of the onboarding form. **What remains open is
  that the escape hatch — self-registering a new tenant instead — still exists and is easy to take by
  accident.**
- Sending the invite by email, rather than the admin copying a link themselves, was named as an open
  question in `23-70` and never decided.
- One working precedent for writing to Keycloak's Admin API already exists:
  `KeycloakDemoIdentityProvisioner` (`Ago.Chat.Infrastructure.Keycloak`, `8-07`/`adr/0058`) — service-
  account `client_credentials` token, cached and semaphore-guarded, used today only to mint demo-tenant
  users. Its own doc comment already names the declarative-user-profile trap (a user created without
  `firstName`/`lastName` is left with pending required actions) this item's design has to solve for
  real invitees, where — unlike the demo case — no name is known up front.

## The design

**Email becomes a required field on invite creation, and Keycloak's own native invite primitive does
the rest** — not a bespoke passwordless/magic-link mechanism, which would duplicate what Keycloak
already does for exactly this case (confirmed against Keycloak's own admin-created-user + required-
actions + `execute-actions-email` workflow, and against how Slack/most SaaS onboarding treats an
invited user as never touching the "create your own workspace" form at all).

1. **Admin creates an invite, must supply an email.** `CreateOperatorInviteHandler` gains a required
   `email` field. The invite still carries its own `CodeHash` — **the code is not replaced by the
   email, it disambiguates which invite an email is redeeming**, because one person's email can
   legitimately hold invites to more than one team at once (an agency operator invited to several
   shops), and each of those has to resolve to the right site/role independently.

2. **AGO talks to Keycloak, not the admin.** On invite creation, AGO calls Keycloak's Admin API to
   create a user for that email. **On a `409` (the email already has a Keycloak identity anywhere on
   the realm — a real, expected case, not an error path to refuse)**, look the existing user up by
   email instead and proceed against that user's id. Either way, the same next step runs: call
   `execute-actions-email` for that user id, with:
   - `requiredActions: [UPDATE_PASSWORD, UPDATE_PROFILE]` — the second one is what lets a brand-new
     invitee supply their own name, since the declarative user profile needs one and invite creation
     never has it to give.
   - `redirect_uri` carrying this invite's own code, so the browser lands back in the app already
     knowing which invite to resolve — replacing `23-27`'s `sessionStorage`-carried code with something
     that survives a real cross-device or cross-browser open of the email link, which `sessionStorage`
     cannot.
   - `lifespan` set to match this invite's own `ExpiresAt` (**7 days**, the author's own chosen common
     denominator) — stated explicitly rather than left to Keycloak's own unrelated default, so the two
     expiries the previous design review flagged as able to silently disagree cannot.
   - The realm's email template driven by **the site's own configured `Locale`** (`Site.Locale`,
     `11-10` — the same source `ago-widget`'s own locale already reads), not a separate language choice
     the admin has to make. Confirm at implementation time that the realm actually has email
     internationalization turned on for more than one locale's template.

3. **Redemption checks the code *and* the authenticated identity's email**, not the code alone — the
   code says which invite, the Keycloak session says who is actually claiming it, and both must agree.
   This is the real security boundary the design now rests on; the old bare-code redemption becomes
   dead code for anything issued from here on.

4. **A registration collision gets a real message.** If the invitee self-registers through the ordinary
   form before opening the invite email, Keycloak refuses (the email already exists) — the console must
   catch that specific failure and show *"у вас есть приглашение, проверьте почту"*, not a raw
   technical error.

5. **Rate-limited, five a day, a hardcoded number in a global config.** Sending invite mail is now a
   real message to an arbitrary third party's inbox from this deployment's own shared Postfix — a
   reputation surface that did not exist before this item (nothing was ever emailed for an invite
   until now). Five per site per day, refused past that with a polite message naming the limit, the
   number itself in `Ago.Chat`'s own global config (not buried in a handler) so it is one line to
   change.

6. **A send failure is not swallowed.** If Keycloak's own attempt to relay the action-token email fails
   at the SMTP layer, that failure must reach the console, not disappear into a log line nobody reads.

7. **A new console screen below the existing operator/team table: the invite list**, shown only when at
   least one invite exists for the site. Columns: email, date sent, status, expiry date. Status
   surfaces the SMTP failure case verbatim when it happens: *"ошибка отправки приглашения, код ошибки
   smtp-сервера: {code}"*. A **"отозвать"** (revoke) button per row: revoking before acceptance means
   the invitee, if they later open the link anyway, sees *"извините, ваше приглашение было отозвано"*
   rather than being let in.

8. **Every existing invite is annulled outright when this ships** — none in production are real yet,
   only test ones, so there is no migration to write and no grandfathering to design. State this
   plainly in the release notes for whoever deploys it, since it is a real, deliberate breaking change
   even though it costs nothing today.

## Out of scope

- Bulk/CSV invite (inviting many people at once) — nothing asks for it yet, and it is a distinct
  feature layered on top of this one, not a blocker to it.
- A lawful-basis review of AGO now creating an account (not merely recording a contact) for a third
  party's email an admin typed on their behalf. Real, and stronger than the precedent
  `visitor_contact_details`' `source: Operator` column already carries — flagged here for
  `personal-data.md` and the eventual lawyer pass this project's own `adr/0076` already names as open,
  not resolved in this item.
- Handling an invitee who never opens the email at all beyond what the existing 7-day expiry already
  does — no reminder/nudge mechanism is being built here.

## Shipped, and what still needs a real realm

`ago-chat#278`/`ago-console#218` build the full mechanism end to end: `email` required on invite
creation; `OperatorInviteEmailProvisioner` (`Ago.Chat.Infrastructure.Keycloak`, `adr/0167`) calling
Keycloak's Admin API to create-or-find an identity and send `execute-actions-email`; redemption
checking the code and the authenticated caller's email together
(`OperatorInviteRedemptionRepository`, revoked checked before email-mismatch); a 5/day/site rate limit
via the existing `IRateLimiter` pattern; an invite-list console screen (email/sent/status/expiry/
revoke); every pre-existing invite annulled by the migration. All of it independently re-verified —
full test suites re-run in both repos (`ago-chat`: 664+1171+21+44+87+1148 tests; `ago-console`: 1331
tests plus the full `ux-gate` suite), the security-critical redemption rewrite and the new
Keycloak-writing class read in full and judged sound.

**Local `docker-desktop` Keycloak's `ago-demo-provisioner` service-account credential drift - fixed,
2026-09-18.** The `client_credentials` grant was refused because the Keycloak-side client secret had
been rotated/regenerated at some point without updating the `infra-credentials` k8s secret to match -
found by comparing the two directly via the Admin API, fixed by resetting the Keycloak-side secret
back to the `infra-credentials` value (`ago-local-dev`), confirmed by a real `client_credentials`
grant succeeding afterward.

**Verified live against the real demo-stand realm, 2026-09-18** (`kcadm.sh` inside the live Keycloak
pod, replicating `OperatorInviteEmailProvisioner`'s own exact calls - `client_id=ago-console`,
`redirect_uri=https://office.reserve-me.ru/redeem-invite?inviteCode=...`, `lifespan=604800`,
`requiredActions=[UPDATE_PASSWORD,UPDATE_PROFILE]`, `locale=ru`):

- **`ConsoleClientId`/redirect-uri pattern**: confirmed. `ago-console`'s registered redirect URIs
  include `https://office.reserve-me.ru/*`, which permits this design's `?inviteCode=` query parameter.
- **Create-or-find-by-email + `execute-actions-email`**: confirmed against a real, pre-existing
  Keycloak identity (`a@golyakov.net`) - the call returned `204 No Content`, and the node's own Postfix
  log shows the real send: `to=<a@golyakov.net>, relay=mx.yandex.net[...]:25, ...
  status=sent (250 2.0.0 Ok: queued on mail-nwsmtp-mxfront-production-41...)`. The mechanism this item
  was least sure of - a real Keycloak Admin API call producing a real, accepted outbound email - works.
- **Locale-driven template language - real bug found and fixed, 2026-09-18.** The author confirmed the
  first test email arrived in English despite `locale=ru`. Root cause: the `ago-chat` realm had
  `internationalizationEnabled: false` - a realm-wide switch, completely independent of any user's own
  `locale` attribute, that forces every themed page and email into a single language regardless. Fixed
  the honest way, not an ad-hoc live edit: added `internationalizationEnabled: true`,
  `supportedLocales: ["en","ru"]`, `defaultLocale: "en"` to `ago-deploy`'s own
  `k8s/base/keycloak-realm-import.json` (`ago-deploy@0c15e73`), applied via `apply -k` (rolled the
  Keycloak pod onto the new ConfigMap) then `k8s/apply-realm-settings.sh` (the realm's own documented
  mechanism, `docs/runbooks/realm-operations.md` - never a bare `kcadm` edit against the live pod,
  which the next realm-settings apply would have silently reverted). Confirmed applied
  (`internationalizationEnabled: true` read back from the live realm) and re-verified with a second
  real send to the same address - full demo-stand smoke suite green afterward (46/46, including
  operator sign-in, proving the Keycloak restart this required broke nothing). **Pending the author's
  own confirmation that the second email actually arrived in Russian** - the mechanism is now
  correctly configured, but only a human reading the inbox closes this box.
- **The hosted `execute-actions-email` page and the full redemption round trip**: still not exercised
  end to end - this test drove Keycloak's own API directly rather than a real operator session through
  `ago-chat`'s own live API, since no real operator credential was available. Opening the real emailed
  link and completing redemption is the one piece still to prove.
- **What Keycloak returns on a genuine SMTP failure**: still unconfirmed - this send succeeded, so it
  proves nothing about the failure path. Would need a deliberately broken relay to observe, not
  attempted here.

**One Done-when is met by a deliberate, stated deviation, not as literally written**: Keycloak's own
hosted self-registration duplicate-email refusal happens entirely inside Keycloak's themed pages and
never reaches AGO's backend or console, so it is not interceptable from application code at all. Built
instead: a new `GET /api/v1/operator-invites/pending-for-me` endpoint that `OnboardingPage` calls
proactively, steering a signed-in identity with a pending invite away from the "create your own
company" form *before* any collision could occur, rather than catching the collision after the fact.

## Done when

- [x] Creating an invite without an email is refused by the API, not merely hidden in the console. —
      `CreateOperatorInviteHandlerTests`, and the column is `NOT NULL` by migration.
- [~] Inviting an email that already holds a Keycloak identity (on this site, a different site, or
      no site at all) succeeds without creating a duplicate account — proven against a real, already-
      existing identity, not only the fresh-account path. **The underlying Keycloak mechanism is now
      live-verified** (2026-09-18, see Outcome above) - `execute-actions-email` against a real,
      pre-existing identity produced a real, accepted send. **Not yet driven through
      `OperatorInviteEmailProvisioner`'s own real 409-then-find-by-email branch** - this test targeted
      the existing user directly rather than exercising the create-call's own 409 response, so the
      code path that decides "create vs. find" is still unverified against a live realm, only its
      final step.
- [ ] The invited user's flow never surfaces the "create your own company" form — an invitee who opens
      the email link ends up as an operator on the inviting site with no branch point where a new
      tenant could be created instead. **Console routing (`CallbackPage`→`/redeem-invite`, auto-submit
      on arrival) unit-tested; the real Keycloak-hosted round trip unverified** - a real invite email
      was sent 2026-09-18 (see Outcome) but not yet clicked through.
- [ ] An invitee who self-registers first (before opening the invite email) sees the specific
      "you have an invitation, check your email" message, not a raw Keycloak error. **Not met as
      literally written — see the deliberate deviation above.**
- [ ] The invite email's language matches the inviting site's own configured `Locale`. **Sent 2026-09-18
      with the Keycloak user's own `locale` attribute set to `ru` (see Outcome) - pending the author's
      own confirmation of which language the email actually arrived in.**
- [x] A sixth invite from the same site on the same day is refused with a message naming the limit; the
      limit itself is one config value, not hardcoded in a handler. — 3 tests in
      `CreateOperatorInviteHandlerTests`, real rate-limiter, not mocked.
- [ ] A genuine SMTP-layer send failure is visible in the console's invite list, with the relaying
      server's own error code, not only in a log. **Wired and tested against a fake provisioner
      returning `SendFailed`; the actual error-code content from a real SMTP failure is unverified.**
- [ ] The invite list (email / sent / status / expiry / revoke) renders under the operator table only
      when at least one invite exists for the site, and revoking before acceptance is proven to
      actually block a later redemption attempt with the stated message.
- [ ] Every invite issued before this change is annulled as part of shipping it, stated in the release
      notes.
