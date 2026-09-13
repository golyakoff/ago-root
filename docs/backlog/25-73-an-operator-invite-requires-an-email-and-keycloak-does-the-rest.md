# 25-73 · An operator invite requires an email, and Keycloak does the rest

- **Stage**: 25
- **Status**: ready — fully designed in dialogue with the author, 2026-09-13, two rounds of critique
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

## Done when

- [ ] Creating an invite without an email is refused by the API, not merely hidden in the console.
- [ ] Inviting an email that already holds a Keycloak identity (on this site, a different site, or
      no site at all) succeeds without creating a duplicate account — proven against a real, already-
      existing identity, not only the fresh-account path.
- [ ] The invited user's flow never surfaces the "create your own company" form — an invitee who opens
      the email link ends up as an operator on the inviting site with no branch point where a new
      tenant could be created instead.
- [ ] An invitee who self-registers first (before opening the invite email) sees the specific
      "you have an invitation, check your email" message, not a raw Keycloak error.
- [ ] The invite email's language matches the inviting site's own configured `Locale`.
- [ ] A sixth invite from the same site on the same day is refused with a message naming the limit; the
      limit itself is one config value, not hardcoded in a handler.
- [ ] A genuine SMTP-layer send failure is visible in the console's invite list, with the relaying
      server's own error code, not only in a log.
- [ ] The invite list (email / sent / status / expiry / revoke) renders under the operator table only
      when at least one invite exists for the site, and revoking before acceptance is proven to
      actually block a later redemption attempt with the stated message.
- [ ] Every invite issued before this change is annulled as part of shipping it, stated in the release
      notes.
