# 25-90 · The invite email carries no fallback code as text

- **Stage**: 25
- **Status**: ready
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

- Decide, first, whether the plaintext-code-as-Keycloak-user-attribute trade-off above is acceptable —
  this item should not proceed to the theme work until that is settled, since it changes what the theme
  work is even allowed to reference.
- If accepted: a custom Keycloak email theme (`ago-deploy`) rendering the invite code as visible text,
  with instructions for where it goes ("after creating your account, paste this into the invite-code
  field on [screen]"), in both `en`/`ru`, verified against a real send.
- If not accepted: name the alternative actually taken instead (a different, still-redundant channel
  that does not require Keycloak to hold the plaintext at all — e.g., a separate transactional email
  this codebase sends itself, outside Keycloak's own relay, the same way `14-09`'s own product email
  channel already sends other mail) or close this as not-planned with the reason.

## Done when

- [ ] The plaintext-in-Keycloak trade-off has an explicit answer from the author, recorded here or in
      an ADR.
- [ ] The invite email (by whichever mechanism the answer above picks) carries the code as plain,
      copyable text, with instructions for where it goes — proven against a real send, not asserted
      from a template file.
- [ ] Both `en` and `ru` render correctly.
