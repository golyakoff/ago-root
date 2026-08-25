# Transactional email: the delivery path self-registration already depends on

- **Stage**: 10 (added 2026-08-25 — Stage 10's own "done when" is false without it, see Goal)
- **Status**: **the provider decision is made and the public path is wired and live; one box remains,
  and it is blocked on DNS rather than on work.** The author chose to **self-host mail entirely,
  outbound and inbound, with no third party at all** — against `adr/0040`'s recommendation of Yandex
  Cloud Postbox, which that ADR's amendment records honestly rather than rewriting to agree.
  Postfix + OpenDKIM run on the node; Keycloak reaches them at `10.42.0.1:25` (the k3s bridge gateway
  — cluster-internal, so committable, unlike the node's public address); the realm's `smtpServer` is
  applied and a **real Keycloak verification mail has been generated, DKIM-signed and delivered**
  (2026-08-25).
  **What is not done is the measurement**: whether that mail lands in an ordinary Inbox or in Spam at
  Mail.ru, Yandex and Gmail. It is deliberately held, not skipped — the MX record was not yet
  published and the zone was propagating unevenly (only 4 of the registrar's 16 authoritative servers
  carried the DKIM/SPF records), and a send during that window would have failed DKIM for most
  receivers and poisoned a fresh IP's reputation for a reason no casual check would reveal. See
  `adr/0040`'s amendment.
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
- **Public: a real sending path** for the demo deployment, configured through the existing
  `infra-credentials` Secret mechanism, with only a `.example` committed. **Answered: a self-hosted
  Postfix on the node, no provider at all** — see Open questions, and `adr/0040`'s amendment for why
  that went against the ADR's own recommendation.
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
- **Email as a conversation channel** — still firmly out (`roadmap.md` Stage 14's channels are MAX,
  SMS, and the gated Telegram/WhatsApp; email is not among them and is not added here by implication).
  **Inbound mail itself is no longer out of scope**, and this bullet used to say it was: the
  self-hosting decision made an MX necessary, because a path with no third party has nowhere else for
  bounces, `postmaster@`/`abuse@` complaints and DMARC `rua=` reports to go. What was built is
  deliberately minimal — a few RFC 2142 aliases delivering to one local mbox, everything else rejected
  at RCPT time. **No IMAP, no webmail, no per-person accounts, no mail service for humans**, and none
  planned. Naming that limit is the point: the next person should not assume there is a mail server
  here that there is not.
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
- [x] The demo deployment sends through a real path, configuration from the existing Secret mechanism,
      only `.example` committed. **Done 2026-08-25, on a self-hosted Postfix rather than a provider.**
      The `KEYCLOAK_SMTP_*` keys travel `.env` → `secretGenerator` → `infra-credentials` → `envFrom`
      exactly as designed, and `k8s/apply-smtp-settings.sh` put them on the live realm. There is no
      credential in them at all — the hop is `10.42.0.1:25`, cluster-internal, no SASL, no TLS needed —
      which is why `.env.example` now carries real committed values instead of placeholders. Proven by
      running it, not by reading config: a `VERIFY_EMAIL` action mail generated by the live Keycloak
      pod (`client=10.42.0.94`) arrived `DKIM-Signature: ... d=reserve-me.ru`, `From: AGO Chat
      <no-reply@reserve-me.ru>`, carrying a real `auth.reserve-me.ru/.../login-actions/action-token`
      link.
- [ ] SPF, DKIM and DMARC exist for the sending address, and a test send lands in an ordinary inbox
      rather than a spam folder — checked in a real mailbox on a domain we do not control.
      **The records exist; the measurement is held, and deliberately.** SPF (`v=spf1 a:mail.reserve-me.ru
      -all`), DKIM (2048-bit, selector `mail`, verified to match the key OpenDKIM holds byte for byte)
      and DMARC (`p=none`) are published, and PTR resolves to `mail.reserve-me.ru`. Two things must be
      true before the result of a send would mean anything:
      **(a)** the zone must agree with itself — at the time of writing only 4 of the registrar's 16
      authoritative servers served the new records, so ~75% of verifiers would have got an
      authoritative `NXDOMAIN` for the DKIM selector, failed DKIM, and cached that negative answer;
      **(b)** the MX must be live — without it, a message landing in Spam cannot be attributed, because
      "fresh IP with no reputation" and "domain that accepts no mail" are different problems with
      different fixes. Neither is work; both are the registrar catching up.
- [x] Password reset works, proven by performing one. It needed more than SMTP: `resetPasswordAllowed`
      was `false`, so the realm never offered the flow at all — the "Forgot Password?" link did not
      exist. Now `true` in the realm import and applied through `apply-realm-settings.sh`. Performed
      end to end in a browser: reset requested → `Reset password` mail in Mailpit → its link opened
      Keycloak's real "Update password" form → new password submitted → **old password now rejected
      with `invalid_grant`, new password returns a token.**
- [ ] A real end-to-end self-registration has been completed on the public deployment by a browser,
      with no admin-API step anywhere in it. **Unblocked technically — the mail path works — but it
      cannot be finished by an agent**, because the step that proves it is reading a mailbox at
      Mail.ru, Yandex or Gmail and seeing whether the message is in Inbox or Spam. Do it once (a) and
      (b) above are true. Everything before that point is verified: the realm sends, Postfix signs and
      delivers, and the action link in the mail is a real one.
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

- **Which sending provider — ANSWERED 2026-08-25: none.** The author chose to self-host mail
  entirely, outbound and inbound, with no third-party service in the path at all, not even a free
  tier. This went **against `adr/0040`'s recommendation** of Yandex Cloud Postbox; that ADR's
  amendment records the reversal, the reasoning, and one thing the recommendation had got factually
  wrong — it listed "outbound port 25 is commonly blocked by hosters" as a reason to reject
  self-hosting, which is true as a generalisation and **false on this hoster**, verified by opening
  SMTP connections from the node to Gmail's, Mail.ru's and Yandex's inbound MX.

  What it buys: no data processor, so `personal-data.md`'s residency constraint stops being a question
  instead of being answered by a vendor's region claim; no per-message cost and no bounce billing; no
  quota (Postbox's default 200/24h would have been a real ceiling); and nothing to cancel, expire or
  re-verify, which matters for a deployment expected to sit unattended.

  What it costs, and this half is not smaller: **reputation is ours to build and to lose** — a fresh
  IP is judged on nothing, and SPF/DKIM/DMARC/PTR are the minimum to avoid automatic penalties, not a
  substitute for sending history. Blocklist monitoring is unowned. Bounces now land in `no-reply@` but
  nothing processes them. The operational surface — a public SMTP port, a milter, a signing key that
  will want rotating, a zone that must stay correct — is this project's to run.

- **`adr/0034`'s registration CAPTCHA is now more urgent than `adr/0040` left it.** That ADR's
  section 6 said the trigger fires the moment SMTP works, and named the provider's own 200-messages-
  per-24-hours quota as the deliberate finite bound replacing the old accidental one. **A self-hosted
  Postfix has no such quota, and none was configured.** So the trigger has fired *and* its named
  replacement does not exist: what actually bounds automated tenant creation today is a deliverable
  mailbox per tenant (weak — disposable-mailbox services exist) and the edge's 30 r/s per-IP flood
  backstop, which `adr/0034` already said is not the answer. Choosing between a CAPTCHA and an
  invite/waitlist gate is a go-to-market decision and stays the author's, but it is no longer
  cushioned by a vendor limit.

- **Nobody reads `postmaster@`/`abuse@` on a schedule.** The aliases exist and deliver, which is what
  makes a complaint from a blocklist operator or a receiving provider *reachable*; nothing notifies on
  arrival. That is where `15-03`'s alerting would belong, and it is not built.
