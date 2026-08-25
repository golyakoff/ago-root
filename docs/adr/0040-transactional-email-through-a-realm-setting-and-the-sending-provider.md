# ADR-0040: Keycloak's SMTP is a realm setting supplied as a Secret; a sink locally; the sending provider is the author's call

- **Status**: Accepted — with one sub-decision deliberately left open and named as such: **which
  sending provider the public deployment uses**. The recommendation, its cost, and its residency
  consequence are on record below; the decision itself is the author's, the same way `15-02`'s backup
  destination and `20-05`'s SMS vendor are (`backlog/10-05-transactional-email-delivery.md`, Open
  questions).
- **Date**: 2026-08-25
- **Stage**: 10

## Context

The realm has had `registrationAllowed: true` and `verifyEmail: true` since `10-01`/`adr/0028`, and
`smtpServer: null` for exactly as long. A visitor could fill in Keycloak's hosted registration form
and Keycloak would accept it, create the account, fail to send the verification mail
(`SEND_VERIFY_EMAIL_ERROR ... error="email_send_failed"`, in its own log), and leave the account
holding a required action that can never be lifted. **No real visitor could finish signing up.** The
account is not merely incomplete — it is stuck, permanently, with no self-service way out.

Password reset was worse than undeliverable: `resetPasswordAllowed` was `false`, so the realm never
offered the flow at all. Two separate gaps that both look like "email does not work".

Three things constrain how this can be fixed, and none of them are hypothetical.

**Realm settings no longer arrive by restart.** `15-01`/`adr/0036` gave Keycloak a database that
survives, which means `--import-realm` is skip-if-exists and a changed `keycloak-realm-import.json`
does not reach a realm that already exists. `ago-deploy/k8s/apply-realm-settings.sh` is the deliberate
step that does. Anything this item adds has to fit that mechanism rather than assume the old one.

**Payment.** `adr/0026` records it plainly: the author's cards are Russian-issued and stopped clearing
at Western merchants after 2022. This is what made the VPS a Russia-region one. It applies unchanged
to a mail vendor — an international provider is not "more expensive", it is *unpurchasable* without a
third-party intermediary.

**Residency.** `architecture/personal-data.md` names `10-05`'s email provider as one of three open
vendor questions its residency constraint binds. Every message this provider handles carries an
account holder's email address, and Russian law requires personal data of Russian citizens to be
processed in databases located in Russia. Until now the deployment satisfied that by accident (a
Russian VPS chosen for cost and latency); this is the first decision that could break it deliberately.

**And one thing this fixes is currently load-bearing as a security control.** `adr/0034` decided the
registration CAPTCHA stays deferred, and its first stated reason is that a spam account gets nothing:
with no SMTP server it can never lift `verifyEmail` and so can never reach `10-02`'s bootstrap
endpoint. That is an accidental bound produced by a broken feature, and this ADR removes it. See
"What replaces the accidental abuse bound" below — an item that quietly deletes another item's stated
control while claiming to fix a bug is not an honest change.

## Decision

### 1. SMTP is realm state, supplied from the existing Secret chain — never from the committed realm file

`smtpServer` is the one realm-level setting that does **not** live in
`ago-deploy/k8s/base/keycloak-realm-import.json`, where `adr/0034`'s login-security policy and
`adr/0028`'s registration flags all live. It comes from `KEYCLOAK_SMTP_*` keys travelling the road
every other credential in this deployment already travels — `.env` → kustomize `secretGenerator` →
the `infra-credentials` Secret → `envFrom` on the Keycloak container — and
`ago-deploy/k8s/apply-smtp-settings.sh` turns those variables into a realm setting through the admin
API. Keycloak itself never reads them; SMTP is realm state, not server configuration.

Three reasons, in order of how much they bind:

1. **The password is a credential.** `architecture/repositories.md`: no secrets, ever — not in a
   fixture, not in a file meant to be fixed later. The realm file is committed and world-readable.
2. **Even the non-secret half must differ per environment.** Locally it is a sink that swallows
   everything; publicly it is a provider that charges per message and represents a real domain. A
   single committed value is wrong in one of the two places, and being wrong in the public direction
   means real verification mail is accepted and silently dropped — worse than not sending at all.
3. **It makes a specific accident impossible rather than merely discouraged.**
   `apply-realm-settings.sh` PUTs the realm file's realm-level fields onto the live realm. Had
   `smtpServer` been in that file, running it against the demo would have reset the demo's mail
   configuration to the local sink. Absent from the file, the field is left alone — that endpoint
   ignores what the representation does not carry.

A related hazard was checked rather than assumed, because it looked like a trap: Keycloak returns the
stored SMTP password masked as `**********`, and `apply-realm-settings.sh` does a read-modify-write of
the whole realm representation, so the obvious worry is that it writes the mask back as the real
password and breaks sending silently. Tested directly against Keycloak's own `realm_smtp_config` table
with a known probe value before and after: **the password survives.** Keycloak recognises its own mask
and keeps the stored value. Either order of the two scripts is safe.

### 2. A mail sink locally — in the `local` overlay and `docker-compose`, and nowhere else

Mailpit (`axllent/mailpit`, pinned) accepts everything on `1025`, forwards nothing, and shows the
result in a web UI. With it, the full browser flow is exercisable locally — register, open the
captured mail, click the link, land verified — instead of the admin-API shortcut
`runbooks/local-dev.md` has carried since `10-01`. The shortcut stays documented; it is now a
convenience for repeated testing rather than the only path past the gate.

It is deliberately **not** in `k8s/base/`. A sink on the demo deployment would accept a real visitor's
verification mail and drop it, which is the silent version of the exact failure this item exists to
fix.

### 3. `resetPasswordAllowed: true`

Found while verifying, and worth separating from the SMTP work: password reset was not merely
undeliverable, it was switched off. Enabling it is a realm-level field in the import file, applied by
`apply-realm-settings.sh` like everything else `adr/0034` chose. A self-service product without
password reset generates support requests the author answers by hand, forever.

### 4. The sending provider: recommendation on record, decision with the author

Structured so the provider is configuration, not a compile-time choice: nothing in `Ago.Chat.*` sends
mail, no `IEmailSender` port is introduced (`10-05`'s own Out of scope, and
`clean-architecture.md`'s warning about an abstraction with no caller), and switching provider is
editing `.env` keys and re-running one script.

The option set, with what each actually costs and requires. Prices are as published on 2026-08-25 and
are the kind of thing that moves; treat them as the shape of the answer, not a quote.

| Option | Cost at this project's volume | What it requires | Where it processes the data |
|---|---|---|---|
| **Yandex Cloud Postbox** | **0 ₽** — first 2 000 messages/month are not billed; beyond that 80.32 ₽/1 000 to 10 k, 70.15 ₽/1 000 to 50 k, 59.98 ₽/1 000 above | A Yandex Cloud billing account, a verified sender address on a domain we control, DNS records including DKIM. Speaks plain SMTP as well as an API | Russia (Yandex Cloud's Russian region) |
| **A Russian ESP with a transactional SMTP product** (SMTP.bz and the Unisender Go / Mailopost / DashaMail / Sendsay family) | SMTP.bz publishes a free tier around 15 000 messages/month and roughly 1 500 ₽ for 50 000; the others were not verified and are not quoted here rather than guessed | An account, a verified sending domain, the same DNS records. Payment by Russian card, ЮMoney or invoice | Stated as Russian-operated; the actual processing location is **not established** and would have to be confirmed in writing before it counts as satisfying the residency constraint |
| **Resend / Postmark / Mailgun / Amazon SES** | Resend: 3 000/month free (100/day, one domain), $20/mo for 50 k. Postmark: 100/month free, $15/mo for 10 k. SendGrid has no free tier at all since July 2025 | A card that clears at a Western merchant | Outside Russia |
| **Self-hosted Postfix on the VPS** | 0 ₽, and no third party at all | Outbound port 25 (commonly blocked by hosters), a PTR record, SPF, DKIM, DMARC, and ongoing blocklist monitoring | Nowhere — the data never leaves the node |

**Recommendation: Yandex Cloud Postbox.** It is the only candidate that satisfies all three binding
constraints at once: payable with a Russian card (`adr/0026`), processing inside Russia so
`personal-data.md`'s residency constraint stays satisfied by decision rather than by luck, and plain
SMTP so no application code enters the path. At this project's volume it costs nothing, and the free
allowance is not a trial — it renews monthly.

Three caveats stated rather than buried:

- **Every accepted message is billed, delivered or not.** Bounces are not free.
- **The default quota is 200 messages per 24 hours**, plus 1 message/second and 10 verified
  identities. Adjustable on request, but it is a real ceiling that a real launch would hit, and it
  must be raised deliberately rather than discovered during an outage. (It is also, for now, a
  feature — see below.)
- **Two things could not be checked without an account and were not invented**: whether an individual
  can hold the billing account or a legal entity is required, and the exact SMTP endpoint and port,
  which come from the provider's own console after domain verification.

The two options worth taking seriously against it are in "Alternatives considered".

**Until the author decides, the demo's `KEYCLOAK_SMTP_*` keys stay blank**, and the deployment behaves
exactly as it does today: a visible failure in Keycloak's log, not a silent one. Everything else in
this item is built and proven.

### 5. SPF, DKIM and DMARC are a precondition for the first real send, not a follow-up

Without them the mail is accepted by the provider, delivered to a spam folder, and looks — from the
visitor's side — identical to the failure this whole item exists to fix. The records belong to the
sending domain and are published before the first real registration, not after the first complaint.

### 6. What replaces the accidental abuse bound

`adr/0034` deferred the registration CAPTCHA partly because "what a spam account currently gets is
nothing": no SMTP means no verification, means no `10-02` bootstrap call, means no tenant. **This ADR
deletes that reason.** `10-02` shipped, so the second half of `adr/0034`'s own stated trigger — "a
self-registered account can create a tenant with no human in the loop *and* `10-05` makes email
verification actually work" — is true the moment mail is configured on the demo. The trigger has
fired, and this ADR says so rather than letting a stated control quietly evaporate.

What actually bounds abuse afterwards, honestly labelled:

- **A deliverable mailbox per tenant.** Real, and weak: disposable-mailbox services exist.
- **The provider's own sending quota.** The recommended provider's default of 200 messages per 24
  hours is a hard, quantified ceiling on tenants created per day — replacing an accidental total bound
  with a deliberate finite one. It is a *rate* limit on the attack, not a gate against it, and it also
  caps legitimate signups, so it cannot simply be left low forever.
- **The edge's 30 r/s per-IP `RateLimitPolicy`**, which `adr/0034` already called a flood backstop
  rather than a registration limit. Unchanged, and still not the answer.

**The question is handed forward, not answered here.** Choosing between a CAPTCHA and an
invite/waitlist gate is a decision about the product's go-to-market, not about mail delivery, and
`adr/0034` already framed it (noting the invite gate is cheaper and needs no third party — which also
avoids attaching a Google call to the sign-up path just as `16-01` writes down a residency
constraint). This ADR's contribution is to record that its trigger condition is now met, so the next
session finds a fired trigger rather than a deferred one. It is not urgent while the demo's SMTP keys
remain blank; it becomes urgent the day they are filled in.

## Consequences

- **Self-registration works end to end for the first time**, locally today and publicly as soon as a
  provider is chosen. So does password reset, which never worked in this project at all.
- **One more post-bring-up step locally.** `docker compose up` or `kubectl apply -k` no longer
  produces a working mail path by itself — `apply-smtp-settings.sh` has to run, like
  `seed/create-demo-tenant.sh` and `create-minio-bucket.sh` already do. The alternative was baking a
  host into the committed realm file, which is exactly what decision 1 refuses.
- **A new class of dependency at signup time.** A visitor's ability to complete registration now
  depends on a third party being up and on their mailbox provider not filing the message as spam.
  Neither is monitored today; `15-03`'s alerting is where that would belong if it is ever worth it.
- **An account holder's email address will leave this system** to whichever provider is chosen. That
  is a data-processing relationship, and `16-01` owns writing it into `personal-data.md`'s inventory
  once the provider is real. This ADR does not edit that file — it states the constraint the choice
  must satisfy and the residency answer for the recommended option.
- **`adr/0034`'s registration-CAPTCHA deferral now rests on one fewer reason than it was written
  with.** Recorded above rather than left for someone to notice.
- **Rotating the SMTP password is `.env` → re-apply the Secret → restart Keycloak → run the script**,
  and the last step is easy to forget, because the Secret changing does not by itself change the
  realm. The runbooks say so.

## Alternatives considered

- **Put `smtpServer` in `keycloak-realm-import.json` with the local sink's values, and override on the
  demo.** The obvious shape, and it makes a fresh local boot work with no extra step. Rejected: it
  puts a committed SMTP host one `apply-realm-settings.sh` run away from resetting the demo's real
  mail configuration to a sink, and the credential still could not live there anyway, so it would have
  split one setting across two mechanisms.
- **Keycloak's `${env.VAR}` placeholder substitution in the realm import file.** Would keep everything
  in one file with no committed secret. Rejected on a fact `adr/0036` already established: the import
  is skip-if-exists, so the file does not reach a realm that already exists — placeholders or not. It
  would work exactly once, on a first boot, which is the case that matters least.
- **Self-hosted Postfix on the VPS.** Genuinely attractive on the constraint that is hardest to
  satisfy: no third party at all, so the residency question does not arise and there is nothing to
  pay. Rejected on deliverability, which is the only thing that matters here — a single VPS IP with no
  sending history, sending to Yandex/Mail.ru/Gmail mailboxes, lands in spam by default; outbound port
  25 is commonly blocked by hosters; and keeping it out of spam is continuous work (PTR, SPF, DKIM,
  DMARC, blocklist monitoring) rather than a setup step. A verification mail in a spam folder is
  indistinguishable, to the visitor, from the failure this item is fixing.
- **A Russian ESP other than Yandex Cloud Postbox.** SMTP.bz's free allowance is larger than
  Postbox's, and for a project that outgrew 2 000 messages/month it could well be the better answer.
  Not recommended today for one reason: its actual data-processing location is not established, and
  `personal-data.md`'s constraint is the sharpest one binding this decision. Worth revisiting with a
  written answer from the vendor.
- **An international provider (Resend, Postmark, SES).** Better tooling, better documentation, and
  free tiers that fit this volume. Rejected twice over: the author cannot pay them (`adr/0026`'s
  payment constraint, unchanged), and they would move account holders' email addresses outside Russia.
  Either objection alone is sufficient.
- **Introduce an `IEmailSender` port in `Ago.Platform.*` now, and send from the application.**
  Rejected, and already argued in `10-05`'s Out of scope: Keycloak speaks SMTP itself with no
  application code in the path, so a port today is an abstraction with no caller — the failure mode
  `clean-architecture.md` names as characteristic of a platform layer. The first real caller arrives
  with `13-01` or `13-02`, and it will sit on top of whatever provider this decision picks.
- **Leave `resetPasswordAllowed: false` and treat password reset as out of scope.** Tempting, since
  the item is nominally about delivery. Rejected: `10-05` asks for both flows explicitly, and the flag
  is one field in a file this change already edits.
