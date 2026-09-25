# 26-113 · Invite (and every Keycloak) email is not sent on the stand — the realm's `smtpServer` is empty

- **Stage**: 26 (but really a stand/realm-operations defect; owned here as the queue).
- **Status**: ready — investigation done (below); the fix (getting `smtpServer` to actually persist on the
  live realm) is the remaining work.
- **Found**: 2026-09-25, by the author: creating an operator invite shows «Приглашение создано, но письмо
  не удалось отправить. Передайте ссылку коллеге вручную.» — the invite is created, the email is not sent.

## What is actually true, confirmed live on the stand

- The operator-invite email is delivered by **Keycloak's own realm relay**, not by `ago-chat`'s SMTP
  (`25-73`: `CreateOperatorInvite` uses Keycloak's admin-created-user + `execute-actions-email`;
  `CreatedOperatorInvite.SendFailed` is true when Keycloak's relay fails at the SMTP layer). So invite
  email == Keycloak realm SMTP, the same path as email verification and password reset.
- **The live `ago-chat` realm's `smtpServer` is empty (`{ }`)** — confirmed via `kcadm get
  realms/ago-chat --fields smtpServer`, read repeatedly. With no realm SMTP, Keycloak cannot send
  anything, so every invite (and verify/reset) email fails.
- The `KEYCLOAK_SMTP_*` values ARE correctly present in the Keycloak container's env and in the node's
  `.env`: `HOST=10.42.0.1`, `PORT=25`, `FROM=no-reply@reserve-me.ru`, `AUTH=false`, no TLS. (These feed
  `apply-smtp-settings.sh`; Keycloak itself never reads them — SMTP is realm state.)
- **Postfix is active on the node**, listening on `0.0.0.0:25` — a real relay exists (`10.42.0.1:25`
  from inside the cluster). (Its ability to relay externally to a real mailbox was not fully verified —
  see remaining work.)
- The realm import JSON deliberately does **not** contain `smtpServer` (kept out on purpose,
  `k8s/base/kustomization.yaml`), and the startup import is `IGNORE_EXISTING` / "Realm already exists,
  import skipped" — so a re-import is **not** clearing it. There is **no reconciler sidecar** (the
  keycloak deployment has one container).

## The anomaly the fix must explain

Running `k8s/apply-smtp-settings.sh` (which PUTs a full `smtpServer` JSON via `kcadm update realms/ago-chat
-f -`) reported success and **its own immediate read-back showed the populated `smtpServer`** — but a
fresh `kcadm get` seconds later, and every read since, shows `{ }` again. So the write appears to take and
then not stick, with no import and no reconciler found to explain the revert. This is the crux to debug:

- Capture the actual HTTP result of the `kcadm update` PUT (verbose/`-x`) — is it really a 2xx, or a
  swallowed 4xx that the read-back's client-side cache masked?
- Ground-truth the DB directly: `keycloak` database, `realm_smtp_config` joined to `realm` where
  `name='ago-chat'` (a clean psql invocation — the quick checks here hit shell-quoting friction and
  returned nothing conclusive). DB populated + admin API empty ⇒ a cache/read issue (try a Keycloak
  restart or cache clear); DB empty ⇒ the PUT genuinely is not persisting.
- Audit Keycloak admin events for `UPDATE`/`REALM` around the apply to see if something immediately
  overwrites it.
- Confirm postfix actually relays a message from the pod network (10.42.0.0/16) to an external mailbox
  (mynetworks/relay config), so that once `smtpServer` is set, mail truly leaves the box — do not declare
  it fixed on a populated realm alone (`acceptance-throughput`: verify real delivery, not plumbing).

## Done when

- [ ] The `ago-chat` realm's `smtpServer` is populated and STAYS populated (survives a re-read and a
      Keycloak restart), pointing at the working relay.
- [ ] A real invite (or password reset) email is confirmed delivered end-to-end to an external mailbox —
      the author sees it arrive, not just a green realm setting.
- [ ] The reason the setting was empty / did not stick is written down here, so it does not silently
      recur after the next deploy.
