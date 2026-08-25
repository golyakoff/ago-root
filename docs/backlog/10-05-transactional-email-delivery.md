# Transactional email: the delivery path self-registration already depends on

- **Stage**: 10 (added 2026-08-25 — Stage 10's own "done when" is false without it, see Goal)
- **Status**: **built and proven locally (2026-08-25); blocked on the author for the one decision it
  was always going to be blocked on** — which sending provider (Open questions below). Everything that
  does not depend on that answer exists and was verified by running it: the local sink, the SMTP
  mechanism, both Keycloak flows end to end through a real browser, and the configuration surface the
  provider values drop into. `adr/0040` records the mechanism and the recommendation. The public half
  of "Done when" cannot be ticked by anyone but the author.
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

- [x] A mock SMTP relay runs in `docker-compose` and the `local` overlay, and the realm points at it.
      Mailpit (`axllent/mailpit:v1.31.0`) in both, plus `ago-deploy/k8s/apply-smtp-settings.sh`, which
      is what actually points the realm at it — `adr/0040` explains why the setting comes from
      `KEYCLOAK_SMTP_*` in the `infra-credentials` Secret rather than from the committed realm file.
      Local-overlay-only on purpose: a sink in `base/` would reach the demo and silently swallow a real
      visitor's mail.
- [x] The full local browser flow completes without the admin-API shortcut: register, open the
      captured mail, verify, reach `10-02`'s bootstrap call. Driven for real in a browser against the
      compose loop (2026-08-25): Keycloak's hosted registration form → "Email verification ... has been
      sent to local-browser-signup@example.test" → the message in Mailpit, `From: AGO Chat (local)
      <no-reply@ago-chat.local>`, subject `Verify email` → its action-token link opened → Keycloak
      completed the flow and redirected to the console's OIDC callback carrying an authorization code.
      Confirmed at the source afterwards, not merely on screen: `emailVerified: true`,
      `requiredActions: []`, and a token for that account with `email_verified: true` — the exact
      state `10-02`'s `RequireKeycloakIdentity`-gated bootstrap endpoint requires.
- [ ] The demo deployment sends through a real provider, credentials from the existing Secret
      mechanism, only `.example` committed. **The mechanism and the `.example` are done**
      (`k8s/overlays/demo/.env.example` carries the full key set, every value a placeholder); the
      provider is the author's call and the keys stay blank until it is made. Blank is deliberate and
      safe: Keycloak then fails visibly in its own log, exactly as today, instead of failing silently.
- [ ] SPF, DKIM and DMARC exist for the sending address, and a test send lands in an ordinary inbox
      rather than a spam folder — checked in a real mailbox on a domain we do not control.
      **Author's, and blocked on the same decision** — the records depend on which provider signs the
      mail.
- [x] Password reset works, proven by performing one. It needed more than SMTP: `resetPasswordAllowed`
      was `false`, so the realm never offered the flow at all — the "Forgot Password?" link did not
      exist. Now `true` in the realm import and applied through `apply-realm-settings.sh`. Performed
      end to end in a browser: reset requested → `Reset password` mail in Mailpit → its link opened
      Keycloak's real "Update password" form → new password submitted → **old password now rejected
      with `invalid_grant`, new password returns a token.**
- [ ] A real end-to-end self-registration has been completed on the public deployment by a browser,
      with no admin-API step anywhere in it. **Author's**, and blocked on the provider decision.
- [x] `local-dev.md`'s "real, unstarted work" sentence, and `10-01`'s and `13-01`'s email deferrals,
      are updated to point here instead of at nobody. (`13-01`'s note was left as it stands — it defers
      *building invitation email*, not delivery, and `adr/0040` gives it the path it would use; nothing
      in it became wrong.)

## Outcome so far

**The break is fixed locally and the mechanism is the deliverable.** `smtpServer` is the one
realm-level setting deliberately kept out of `keycloak-realm-import.json`: it carries a credential,
its correct value differs between a local sink and a paid provider, and — the reason that turns a
preference into a rule — `apply-realm-settings.sh` PUTs that file's realm-level fields onto the live
realm, so a committed SMTP host would sit one script run away from resetting the demo's mail
configuration to a sink. `adr/0040` argues all three.

**Two things were checked rather than assumed, and one of them was a lie the tooling told.**
`kcadm get realms/X --fields smtpServer` prints `{ }` for a correctly-applied configuration — its
field filter does not descend into a Map — which reads exactly like "nothing was applied". The
verification line in `apply-smtp-settings.sh` reads the whole representation instead, and says why.
And the read-modify-write hazard that looked real is not: Keycloak returns the SMTP password masked as
`**********`, but recognises its own mask on the way back in — a probe password read straight out of
Keycloak's `realm_smtp_config` table before and after an `apply-realm-settings.sh` run was unchanged.
Either script order is safe.

**The Kubernetes half was verified as far as it can be without touching the demo**: the `local` overlay
renders with Mailpit and the `KEYCLOAK_SMTP_*` keys in `infra-credentials`, the demo overlay renders
with no Mailpit anywhere in it, the manifests are accepted by a real API server, Mailpit reaches Ready
on the local cluster with its own exec probes, and Keycloak's own pod completed an SMTP transaction to
`mailpit:1025` (`250 Ok: queued`). The full send was proven on the compose loop; the two targets share
the script and the realm, and differ only in how the variables reach the container.

**What this costs elsewhere, stated because it is easy to miss.** `adr/0034` deferred the registration
CAPTCHA partly because a spam account "gets nothing" — with no SMTP it could never lift `verifyEmail`,
so it could never reach `10-02`'s bootstrap endpoint. `10-02` has shipped, so **`adr/0034`'s own stated
trigger fires the moment the demo's SMTP keys are filled in.** `adr/0040` records that, names what
replaces the accidental bound (a deliverable mailbox per tenant; the provider's own default 200
messages/24h as a deliberate finite ceiling; the edge's flood backstop, which `adr/0034` already said
is not the answer), and hands the actual choice — CAPTCHA or invite/waitlist gate — forward rather
than answering a go-to-market question inside a mail-delivery item. Not urgent while the keys are
blank; urgent the day they are not.

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

  **Researched and narrowed, 2026-08-25 — still the author's to answer.** `adr/0040` carries the full
  comparison; the short form:

  - **Recommended: Yandex Cloud Postbox.** 0 ₽ at this project's volume — the first 2 000 messages a
    month are not billed, and beyond that 80.32 ₽/1 000 up to 10 k, 70.15 ₽/1 000 to 50 k, 59.98
    ₽/1 000 above. Needs a Yandex Cloud billing account, a sender domain verified there, and DNS
    records including DKIM. Speaks plain SMTP, so no application code enters the path. **Processes in
    Russia**, which is the only reason it clears `personal-data.md`'s constraint by decision rather
    than by luck. Two things not checkable without an account and therefore not asserted: whether an
    individual may hold the billing account, and the exact SMTP endpoint and port. Two caveats that
    are certain: every accepted message is billed whether it is delivered or not, and the default
    quota is **200 messages per 24 hours** (plus 1/second, 10 verified identities) — adjustable on
    request, but a real ceiling a real launch would hit.
  - **A Russian ESP instead** (SMTP.bz, or the Unisender Go / Mailopost / DashaMail / Sendsay family).
    SMTP.bz publishes a larger free allowance — around 15 000 messages a month, roughly 1 500 ₽ for
    50 000 — and takes Russian cards, ЮMoney or an invoice. The blocker is not price: its actual
    data-processing location is **not established**, and the residency constraint is the sharpest one
    binding this decision. Worth revisiting with a written answer from the vendor; the pricing of the
    others was not verified and is deliberately not quoted here rather than guessed.
  - **Not viable: Resend, Postmark, Mailgun, Amazon SES.** Better tooling and free tiers that would fit
    (Resend 3 000/month, Postmark 100/month; SendGrid has had no free tier since July 2025), and
    rejected twice over — `adr/0026`'s payment constraint means the author cannot pay a Western
    merchant at all, and every one of them moves account holders' email addresses outside Russia.
  - **Self-hosted Postfix on the VPS** is the only option with no third party and therefore no
    residency question. Rejected on the thing that actually matters: a single VPS IP with no sending
    history lands in spam at Yandex/Mail.ru/Gmail by default, outbound port 25 is commonly blocked, and
    staying out of spam is continuous work rather than a setup step. A verification mail in a spam
    folder is, from the visitor's side, the same failure this item exists to fix.

  Answering this unblocks the three unticked boxes above and nothing else — the mechanism is built,
  and switching provider is editing `.env` keys and re-running one script.
