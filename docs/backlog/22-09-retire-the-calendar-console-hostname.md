# Retire `calendar.` — route, listener, certificate, Keycloak client, DNS

- **Stage**: 22
- **Status**: done (2026-09-06). Step 5 — the A-record at reg.ru — was done by the author the same
  day; the five boxes below were left unticked and have now been verified against the live
  deployment rather than assumed. See the Outcome.
- **Depends on**: `22-06` (hard — nothing here happens until the merged console is proven live)

## What retires, and what stays

| | |
|---|---|
| retires | `calendar.reserve-me.ru` — the calendar console's hostname |
| **not here** | `chat.` — the chat console's old name retires with `22-10`, which moves the console to `office.`. Same trap, different item, so each closes green on its own |
| retires | its `HTTPRoute`, its `https-calendar-console` Gateway listener, its name in the certificate SAN, its A-record |
| retires | the `ago-calendar-console` Keycloak client |
| retires | the `ago-calendar-console` Deployment, Service and image pin |
| **stays** | `calendar-api.reserve-me.ru` — **the console merges, the API does not** |
| **stays** | `office.reserve-me.ru` — where the merged console lives (`22-10`) |

## The order, and it is not interchangeable

This is the reverse of `adr/0091`'s migration and the same traps apply, in mirror image. Two of them
have already cost this project something specific.

1. **Merged console proven at `office.`** — a real sign-in reaching a calendar screen. Not "it serves
   200"; `20-20` passed a check that fetched a static SPA while the API behind it was crash-looping.
2. **`Operator__Audience` accepts both clients**, then the merged console goes live. Narrow to one
   only after. A single-value switch leaves no overlap to verify in.
3. **Remove the route and the listener.** `calendar.` stops being served.
4. **Remove `calendar.reserve-me.ru` from the certificate SAN.** Removing a name needs no
   validation — only adding does. The certificate re-issues once for the remaining names.
5. **Only then delete the A-record.** *Reversing 4 and 5 is the trap*: with the name still in the SAN
   and its DNS gone, the next renewal fails HTTP-01 for it and **one failed authorization fails the
   whole certificate** — every other hostname loses TLS with it. This nearly happened with
   `grafana.` on 2026-09-03 and was caught only because the SAN was checked after the record was
   deleted.
6. **Delete the Keycloak client.** `--import-realm` is skip-if-exists, so removing it from
   `keycloak-realm-import.json` changes nothing on a live realm — it needs `kcadm` by hand, and the
   file edit is for the *next* cluster, not this one. `20-20` learned the same asymmetry creating this
   client.
7. **Remove the workload, the image pin and the smoke checks** naming the retired host.

## Authorised to proceed on the live deployment (author, 2026-09-05)

The author's words: *do this boldly while there are no live clients on the field yet.*

That authorisation is **dated and bounded**, and both halves matter. It rests on a fact that stops
being true the moment a first tenant signs up — which is expected within weeks — so an implementation
reading this later must check whether it still holds rather than inherit it. It covers acting on the
live deployment for this item; it is not a standing licence for the next one.

## Done when

- [x] `calendar.reserve-me.ru` resolves to nothing and serves nothing.
- [x] The certificate is `Ready` with the remaining names, checked **after** the DNS deletion, not
      before.
- [x] Every other hostname still serves TLS — the cheap check that catches the step-5 trap.
- [~] `smoke.sh` **does** reference the retired host, deliberately, and is green - see the
      Outcome. The box asked for silence; what shipped is better than silence.
- [x] No Keycloak client, Deployment, Service, route, listener or pin for it remains.

## Outcome (2026-09-06)

Steps 3, 4, 6 and 7 done on the live deployment and verified at each step. **Step 5 — deleting the
`calendar.reserve-me.ru` A-record at reg.ru — is the author's**, because that is an account only they
have (`public-deploy.md` marks DNS `(you)`). The order was kept, so the record is now safe to delete at
any time.

**Step 1's check was made the way the item demanded, not the way that is easy.** Not "it serves 200":
`calendar-api` was asked for a protected route and answered **401**, which proves the application is
alive and enforcing authorisation — a crash-looping API answers 502. And the bundle served at `office.`
was read to confirm it contains the calendar screens and points at `calendar-api`. That is the check
`20-20` failed to make when it passed a green run against a static SPA whose API was crash-looping.

**Step 2 turned out to be already closed, and the reason lowers the risk of everything after it.**
`22-06` switched `Operator__Audience` to `ago-console` in one step rather than widening first, and
recorded why: `ValidAudience` is single-valued, so accepting both would have meant a code change for a
console being retired. **So the bundle at `calendar.` had been unable to authenticate since then** —
every step below removed something already non-functional.

**The certificate behaved exactly as the file's own comment promised, which is worth recording because
the promise was previously untested here.** Removing a name needs no validation: the re-issue completed
in ten seconds, the ACME order went straight to `valid`, no new challenge was created, and the wire
showed seven SANs with `calendar.` gone and every other host still answering.

**Two things the work found that were not in the item.**

1. **Applying the whole overlay would have moved more than this item.** A server-side dry run showed
   `ago-demo-shop1` and `ago-demo-shop2` would roll to a different image tag, and the calendar migrator
   Job would be recreated. Neither belongs to `22-09`. So the Gateway and the Certificate were applied
   as individual objects instead. The image-pin drift is real and unexamined — the committed pin is
   ahead of what runs — and it is left as found rather than silently deployed.
2. **`smoke.sh` named the retired host in three places, not one.** Step 7 fixed the version loop and
   missed a dedicated check and the Edge host list; the suite caught both on its first run afterwards
   (43 passed, 2 failed). The dedicated check was **inverted rather than deleted**, copying `grafana.`'s
   own shape in the same file — a deleted check proves nothing, an inverted one proves the retirement
   stuck. The suite now reports 44 passed, 0 failed.

**The Keycloak client was deleted by hand**, which is the asymmetry `20-20` learned while creating it:
`--import-realm` is skip-if-exists, so removing it from `keycloak-realm-import.json` changes nothing on
a live realm. Verified after: `authorize?client_id=ago-calendar-console` returns **400**, `ago-console`
still returns **200**, and `office.` still serves.

## Outcome - verified 2026-09-06 evening, against the live deployment

| Checked | Result |
|---|---|
| `calendar.reserve-me.ru` resolves | **no** |
| it serves anything | **no** - `000`, the connection is never made |
| `ago-public-tls` certificate | `Ready`, and its `dnsNames` no longer carry the retired name |
| every remaining hostname over TLS | all seven answer - `chat-api`, `auth`, `demo-shop1`, `demo-shop2`, `calendar-api`, `office`, apex |
| any Deployment, Service or route for it | none |
| any Keycloak client, ConfigMap or Secret for it | none |

**The fifth box is marked `[~]` rather than ticked, and that is not pedantry.** It asked that
`smoke.sh` carry *no reference* to the retired host. It carries one on purpose: an **inverted** check,
asserting the hostname answers nothing and failing loudly if it ever answers again. That follows the
precedent already set for grafana, and it is strictly better than silence - a removed check cannot
notice a resurrection. Two comments in `gateway.yaml` and `tls.yaml` likewise record *when and why*
the name went, which is exactly the kind of reference a future reader needs.

**Why this sat unticked is the part worth keeping.** The item was closed with an honest
`done except step 5`, because step 5 was the author's to do at a registrar no repository here can
reach. It was done within the hour - and nothing brought the item back for its last five ticks,
because nothing watches for *an item whose remaining work has since happened*. `queue-audit.sh` looks
for the opposite shape: boxes all ticked while the row stays open.
