# ADR-0167: Operator invite email uses Keycloak's native invite primitive, not a bespoke passwordless flow

- **Status**: Accepted
- **Date**: 2026-09-13
- **Stage**: 25

## Context

`13-01`/`23-70` built an operator invite as a bare, high-entropy code: an admin generates one, copies
a link built around it, and distributes it however they like (Slack, email, in person). The gap
`25-73` closes is what happens once the invitee opens that link with no Keycloak identity at all
(`docs/backlog/25-73-*.md`'s own "Found": a real invitee landed on a login page and, had they
self-registered instead, would have created their own tenant rather than joined the inviting site).

Closing that gap needs *something* that creates a real, usable Keycloak identity for an address the
admin only typed, not one the invitee has proven they control yet, and gets a credential into that
person's hands without AGO ever holding or transmitting a password itself. Two shapes were available:
build that mechanism ourselves, or drive the one Keycloak already ships for exactly this case
(admin-created user + required actions + `execute-actions-email`). `KeycloakDemoIdentityProvisioner`
(`8-07`/`adr/0058`) already established that this codebase is willing to write to Keycloak's Admin API
from `Ago.Chat.Infrastructure.Keycloak`, for a different purpose (minting disposable demo identities
with a password AGO itself generates).

## Decision

`OperatorInviteEmailProvisioner` (a new class, not an extension of `KeycloakDemoIdentityProvisioner`)
creates or finds a Keycloak user for the invitee's email and calls Keycloak's own
`execute-actions-email` endpoint with `requiredActions: [UPDATE_PASSWORD, UPDATE_PROFILE]`. Keycloak
renders and sends the email itself, over its own configured SMTP relay, using its own hosted
required-actions UI for the invitee to set a password and (since none was known at invite time) a
name. AGO never generates, holds, or transmits a password for this identity at any point - the
identity has no usable credential at all until the invitee sets one through Keycloak's own page.

The invite's own code/hash mechanism is not replaced - it survives as the thing that says *which*
invite (and therefore which site and role) an incoming redemption is for, since one email can hold
invites to more than one site. What Keycloak's primitive replaces is only the delivery and credential
bootstrap: the admin no longer copies a link by hand, and no bespoke "send this person a magic link"
mechanism was built to do it.

## Consequences

**Positive.** No second identity/credential-issuance system to build, secure, or reason about
alongside Keycloak - `execute-actions-email`'s required-actions flow, password policy, rate limits and
localized email templates are Keycloak's own, already relied on for every other sign-in in this
product. AGO's own attack surface for "mint a credential for a stranger" does not grow: it still never
holds a password for anyone it has not authenticated.

**Negative.** AGO is now dependent on Keycloak's own SMTP relay being configured and healthy for a
capability the console's own success/failure messaging has to represent honestly (`25-73`'s own point
6) - a dependency that did not exist before this item, since nothing was ever emailed for an invite
until now. The realm's own email-template internationalization (rendering in the inviting site's
`Locale`) is configuration this application does not control or own; if the realm has only one
locale's template enabled, an invite still sends, but not necessarily in the right language - a real,
external failure mode this ADR does not resolve, only accepts. The `execute-actions-email` endpoint's
own Admin REST response does not reliably distinguish "the SMTP relay itself failed" from other
failure shapes at the HTTP-status level, so the SMTP error code this item's own console screen shows
is best-effort, not a guaranteed passthrough of the underlying relay's own response code.

## Alternatives considered

**A bespoke passwordless/magic-link mechanism** (AGO generates its own signed, time-limited token;
emails it directly via `Ago.Chat.Infrastructure.Email`; a redemption endpoint exchanges the token for
a session). Rejected: this duplicates required-action semantics, password-set UX, and localized email
templates Keycloak already has, for no capability the built-in primitive lacks - the same reasoning
`8-07`/`adr/0058` used to justify writing to Keycloak's Admin API at all rather than issuing AGO's own
tokens for the demo case. It would also mean AGO briefly minting and transmitting a credential
(or a credential-equivalent token) for an identity it has not authenticated, which the chosen design
avoids entirely.

**Extending `KeycloakDemoIdentityProvisioner` itself** rather than writing a new class. Rejected: that
class's own shape (no user lookup, blank-but-verified `.invalid` email, no required actions) is
correct for its own case and wrong for this one on every one of those points; folding both into one
type would make each harder to read for the other's sake, not easier.
