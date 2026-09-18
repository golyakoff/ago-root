# 25-90 · The invite email carries no fallback code as text

- **Stage**: 25
- **Status**: done — `ago-chat#332`
- **Depends on**: nothing
- **Found**: `25-85`'s own point 4 — "the invite email itself should also carry the code as visible
  text, as a second, independent channel" — investigated and deliberately not built in that item's own
  pass; this is the residual, given its own number per `CLAUDE.md` rule 14 rather than left as an
  unticked box on `25-85`.

## What `25-85` found, investigating this

The invite email is Keycloak's own stock `execute-actions-email` template (`adr/0167`,
`OperatorInviteEmailProvisioner.SendActionsEmailAsync`) — that Admin REST call takes exactly three
query parameters (`client_id`, `redirect_uri`, `lifespan`) and a JSON body naming the required
actions. There is no parameter through which this codebase can hand Keycloak an arbitrary value (the
invite code) for its own template to render as text. The email's content is entirely Keycloak's own
FreeMarker template for the realm's active theme, using only the context variables Keycloak itself
supplies (`user`, `realm`, `link`, `linkExpiration`, `requiredActions`) — none of which carry this
product's own invite code, because Keycloak has no concept of one. The `link` variable is the signed
action-token URL, not the `redirect_uri`; the invite code embedded in that `redirect_uri`
(`?inviteCode=...`) is not recoverable from `link` by a template.

**Two ways to actually get the code into that email, both real scope, neither attempted here:**

1. **A custom email theme overriding `executeActions.ftl`/`executeActions-text.ftl`**, mounted the way
   `ago-deploy/k8s/base/keycloak-theme/` already mounts a custom *login* theme (checked — no email
   theme exists there today). This is a real theme-authoring task: two new FreeMarker templates (HTML
   and plain-text, Keycloak sends both parts), realm config pointing the email theme at it, and
   verification in both `en`/`ru` locales against a real send (the same "not verified against a live
   realm" gap `OperatorInviteEmailProvisioner`'s own doc comment already names for the locale
   attribute).
2. **Getting the plaintext code into the template's own reach at all.** A FreeMarker template still
   needs *some* value to render — the most direct route is a Keycloak user attribute
   (`OperatorInviteEmailProvisioner.CreateOrFindUserAsync` already sets a `locale` attribute the same
   way), read back in the template as `${user.attributes.pendingInviteCode}`. **This is the part that
   needs a real decision, not just an implementation:** it means the plaintext invite code sits in
   Keycloak's own user-attribute storage, indefinitely (or until overwritten by a later invite) —
   which is a real, if narrow, departure from `OperatorInvite`'s own stated design that the code "is
   never stored or logged in plaintext form anywhere" (`OperatorInvite.cs`'s own remarks on
   `CodeHash`). Whether that trade-off is worth taking for this one redundant channel is a decision for
   the author, not something a worker should decide unilaterally by building it.

## Scope

**Decided by the author, 2026-09-18: the plaintext-in-Keycloak trade-off is rejected.** The code must
never sit in Keycloak's own storage. Instead: a separate, second email, sent by `ago-chat` itself,
outside Keycloak's relay entirely.

`INotificationMailSender`/`NotificationMailSender`
(`Ago.Chat.Infrastructure.Email/NotificationMailSender.cs`) already exists and is already used for
exactly this shape of transactional mail (operator inactivity warnings via `InactivityWatchdogJob`) -
`SendAsync(NotificationMailMessage(To, Subject, Body), ct)`, generic, not coupled to the visitor-
conversation shape `EmailChannelAdapter` owns. **No new SMTP infrastructure is needed.**

`CreateOperatorInviteHandler.HandleAsync` already has both the operator's email address and the
plaintext code in hand at the point it calls `OperatorInviteEmailProvisioner.ProvisionAndSendAsync`
(`OperatorInviteProvisionRequest.Code`) - fire a second `INotificationMailSender.SendAsync` call from
that same call site, right after (or before) the Keycloak action-email, carrying the code as plain,
copyable text plus instructions for where it goes. Two independent emails land in the operator's
inbox; neither depends on the other arriving, and Keycloak's own template is untouched.

- Both `en`/`ru` subject+body strings, resolved the same way this codebase's other locale-aware
  transactional copy already is (check `NotificationMailSender`'s existing callers for the convention).
- Verified against a real send, not asserted from a template - the same standing bar every other email
  path in this codebase already gets held to.

## Done when

- [x] The plaintext-in-Keycloak trade-off has an explicit answer from the author: rejected. A second,
      independent email is sent instead.
- [x] A second `NotificationMailSender` email fires from `CreateOperatorInviteHandler`, carrying the
      invite code as plain, copyable text with instructions for where it goes — proven against a real
      send, not asserted from a template file.
- [x] Both `en` and `ru` render correctly.
- [x] Keycloak's own `execute-actions-email` template and its call are untouched by this item.

## Outcome

`OperatorInviteCodeMailTemplate` builds one bilingual (ru above en) message, following
`NotificationMailSender`'s own two existing callers' established convention rather than a per-locale
switch. `CreateOperatorInviteHandler.SendInviteCodeFallbackEmailAsync` fires unconditionally,
independent of the Keycloak send outcome, wrapped in its own fault boundary (logged and swallowed on
failure - never allowed to fail invite creation). The redeem instructions point at the real
`/redeem-invite` console route (verified against `ago-console`'s own `App.tsx`). Proven through the
real handler and real HTTP endpoint wiring with a recording fake - the identical "fake this port,
trust `EmailSmtpClient`'s own wire-level tests separately" precedent `InactivityWatchdogJobTests`
already set for this same port, not a gap this item introduced. Keycloak's own template/call confirmed
untouched by diff. Full suite green: Domain 741, Application 1404, FakeCrm 21, Architecture 52,
Concurrency 89, Integration 1376. `ago-chat#332`.
