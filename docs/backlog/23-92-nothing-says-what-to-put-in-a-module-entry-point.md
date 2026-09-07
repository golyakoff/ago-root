# nothing says what to put in a module entry point

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-87`, which made provisioning work at all and so made this the next thing to stop it.
- **Found**: 2026-09-07, by the author trying to grant the calendar on the demo stand and getting a 404.

## What happened

The author filled the platform owner's grant form, put `https://golyakov.net` in **Entry point**, and got
*Module 'calendar' is unreachable: module answered 404 Not Found*. The error was correct and the form gave
them nothing to be correct with.

**Nowhere states the value.** `module-grant-and-revoke.md`'s field table says only *"where the module is
reached"*. The console's own hint says *"an absolute https URL"*, which is **wrong in two ways at once**:
the scheme is validated nowhere — not by `EnabledModule.EntryPoint`, which is a bare `Uri`, and not by the
console — and for this deployment the working value is not https.

## The answer, established by probing rather than by reading

- **`https://calendar-api.reserve-me.ru` does not work, deliberately.** The `ago-calendar-api` HTTPRoute is
  an allowlist: `/` as an **Exact** match, plus `/healthz`, `/api/v1/console`, `/api/v1/calendars`,
  `/api/v1/embed` and `/api/v1/me` as prefixes. `/api/v1/module-registrations` is not among them, so the
  gateway answers before the application does. The provisioning surface is not on the public internet,
  which is right.
- **`https://ago-calendar-api:443` does not work either.** The Service does serve 8443, but `ago-chat-api`
  mounts no volume except `/tmp` — it does not carry `22-24`'s internal CA, so the certificate would not
  validate.
- **`http://ago-calendar-api` works.** A `PUT` to `http://ago-calendar-api/api/v1/module-registrations/{siteId}`
  from inside the namespace answers **401** — reachable, routed, and refusing only for the missing
  provisioning secret.

## Scope

- **Write the value down where somebody granting a module will read it** — the runbook's field table, not
  only here.
- **Fix the console hint.** It should describe what the field is for and stop asserting a scheme that is
  neither required nor correct. Whether a scheme *should* be constrained is `23-93`'s question, not a
  hint's job.
- **Say why the public hostname is not it**, in one sentence, or the next person will try it and read the
  gateway's 404 as a broken calendar.

## Where this is likely to go wrong

- **The value is deployment-specific.** `http://ago-calendar-api` is this cluster's Service name. The
  runbook should say what the value *is* — the module deployment's own in-cluster address — and give this
  deployment's as the worked example, rather than presenting one string as universal.
- **A per-site field holding an infrastructure address is odd**, and worth a sentence. It is
  per-(site, module) because a module deployment could in principle differ per site; in practice every
  site on one deployment gets the same string typed again, and a typo becomes a 404 an hour later.

## Done when

- [ ] Somebody granting a module can find the correct entry point without probing the cluster.
- [ ] The console's hint says something true.
- [ ] Why the public hostname is not the answer is written down.
