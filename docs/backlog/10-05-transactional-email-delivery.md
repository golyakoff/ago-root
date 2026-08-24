# Transactional email: the delivery path self-registration already depends on

- **Stage**: 10 (added 2026-08-25 — Stage 10's own "done when" is false without it, see Goal)
- **Status**: ready — scoped so the one real cost decision (which sending provider, Open questions
  below) is named rather than invented, the same way `14-03`, `20-05` and `15-02` handle theirs;
  everything else here can be built before it is answered
- **Depends on**: nothing new architecturally. It needs `15-01-keycloak-persistent-user-store.md` to
  land before the flow is worth anything on the demo deployment — verifying an account whose user row
  disappears on the next pod restart proves little — but the two are independent pieces of work and
  either can be built first.

## Goal

A real visitor can complete self-registration: fill in Keycloak's hosted form, receive the
verification mail, click the link, and reach `10-02`'s bootstrap call. Today they cannot. The demo
realm has `registrationAllowed: true` and `verifyEmail: true` with `smtpServer: null`, so Keycloak
accepts the registration and then fails to send anything — `SEND_VERIFY_EMAIL_ERROR ...
error="email_send_failed"` in its own log, already found live and already written down in
`runbooks/local-dev.md`. The account exists, the required action never lifts, and the visitor is
stuck. Stage 10's "done when" — an account, site and operator created end to end by a real visitor —
cannot be true until this exists.

## Context to read first

`docs/runbooks/local-dev.md`'s "Completing self-registration locally" section in full. It is the
honest account of this gap: the exact Keycloak error, the correction of an earlier claim that
Keycloak logs the mail to its own console (it does not), the admin-API shortcut used instead, and the
sentence this item exists to retire — "adding a mock-SMTP relay (e.g. MailHog) to the local compose
stack is real, unstarted work". `docs/backlog/10-01-self-registration-identity-flow.md`'s out-of-scope
note — "any email-sending/deliverability setup ... beyond enabling Keycloak's built-in Verify Email
required action", the first link in the chain. `docs/backlog/13-01-operator-invitations-and-seat-
entitlement.md` — the second link, which cites `10-01` as its precedent for not building email
delivery either and instead has an admin copy an invitation link by hand. `adr/0028` — why Keycloak's
own hosted registration flow was chosen, "including its own email-verification gate"; that gate is
exactly what has no delivery path. `adr/0026` — the deployment this has to send mail from, and its
domain. `docs/architecture/clean-architecture.md`'s qualifying rules for `Ago.Platform.*` — relevant
to the port question this item deliberately does not answer (see Out of scope).

## Scope

- **Local: a mock SMTP relay** (MailHog, Mailpit, or equivalent) in `docker-compose` and in the
  `local` Kustomize overlay, with the realm's `smtpServer` pointed at it. After this, the full browser
  flow — register, open the captured mail, click through, land verified — is exercisable locally
  without the admin-API shortcut. Keep the shortcut documented; it stays useful for automated and
  repeated testing, and this item makes it a convenience rather than the only path.
- **Public: a real sending provider** for the demo deployment, configured through the existing
  `infra-credentials` Secret mechanism, with only a `.example` committed. Which provider is the open
  question below.
- **Sender identity on the real domain**: SPF, DKIM and DMARC records for whatever address mail is
  sent from. Without them the mail is sent and silently filed as spam, which looks exactly like the
  current failure from the visitor's side. This is the part that is easy to skip and then be puzzled
  by.
- **Prove both flows Keycloak can now actually run**: email verification at registration, and password
  reset. Password reset has never worked in this project either, for the same missing-SMTP reason, and
  a self-service product without it generates support requests the author has to answer by hand.
- **Verified end to end on the public deployment**, from a mailbox that is not the author's own
  sending domain — a real registration by a real browser, the mail arriving in an ordinary inbox, and
  the account reaching `10-02`'s bootstrap call. `CLAUDE.md`'s standing bar: run it, do not assert it.
- **Retire the stale claims**: `local-dev.md`'s "real, unstarted work" sentence, and the out-of-scope
  notes in `10-01` and `13-01` that defer email to nobody in particular.

## Out of scope

- **An `IEmailSender` port in `Ago.Platform.*`, or any application-level mail sending.** Deliberate,
  and worth stating rather than leaving as an omission: nothing in `Ago.Chat.*` sends mail today.
  Keycloak talks SMTP itself, from its own configuration, with no application code in the path — so
  introducing a port now would mean building an abstraction with no caller, which is precisely the
  premature generalisation `clean-architecture.md` names as the platform layer's characteristic
  failure. The first genuine in-app caller arrives with Stage 13 (`13-01`'s operator invitations, or
  `13-02`'s payment-state notifications, whichever is built first); the port gets designed there,
  against a real use case, and this item's provider choice is what it will sit on top of.
- Email templating and branding beyond what Keycloak's own default templates produce. Real work, and
  it belongs with `11-05`'s design pass or a follow-up to it, not here.
- Inbound mail of any kind — no address receives mail, and email is not a conversation channel
  (`roadmap.md` Stage 14's channels are MAX, SMS, and the gated Telegram/WhatsApp; email is not among
  them and is not being added here by implication).
- Operator invitations themselves (`13-01`) — this item gives that one a delivery path if it wants one
  later; it does not change what `13-01` builds.
- Bounce handling, suppression lists, or send-rate accounting. Nothing at this volume needs them, and
  each would be inventing a requirement.

## Done when

- [ ] A mock SMTP relay runs in `docker-compose` and the `local` overlay, and the realm points at it.
- [ ] The full local browser flow completes without the admin-API shortcut: register, open the
      captured mail, verify, reach `10-02`'s bootstrap call.
- [ ] The demo deployment sends through a real provider, credentials from the existing Secret
      mechanism, only `.example` committed.
- [ ] SPF, DKIM and DMARC exist for the sending address, and a test send lands in an ordinary inbox
      rather than a spam folder — checked in a real mailbox on a domain we do not control.
- [ ] Password reset works, proven by performing one.
- [ ] A real end-to-end self-registration has been completed on the public deployment by a browser,
      with no admin-API step anywhere in it.
- [ ] `local-dev.md`'s "real, unstarted work" sentence, and `10-01`'s and `13-01`'s email deferrals,
      are updated to point here instead of at nobody.

## Open questions

- **Which sending provider.** A real choice with a real monthly cost and a real constraint the other
  vendor questions in this backlog do not have: the deployment is Russian-hosted (`adr/0026`), and
  several of the obvious international providers are awkward or unavailable from it. The author's
  call, the same way `15-02`'s backup destination and `20-05`'s SMS vendor are. Everything else in
  this item — the local relay, the flows, the DNS records, the verification — can be built first.
  **Constrained since 2026-08-25** by `architecture/personal-data.md`: every message this provider
  handles carries an account holder's email address, so the choice is a data-residency decision as well
  as a cost one — which sharpens rather than loosens the "several obvious providers are awkward from
  here" observation already made above. `16-01` records the constraint.
