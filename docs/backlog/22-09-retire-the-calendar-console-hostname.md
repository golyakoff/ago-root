# Retire `calendar.` — route, listener, certificate, Keycloak client, DNS

- **Stage**: 22
- **Status**: done except step 5 (2026-09-06) — the A-record is the author's, at reg.ru
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

- [ ] `calendar.reserve-me.ru` resolves to nothing and serves nothing.
- [ ] The certificate is `Ready` with the remaining names, checked **after** the DNS deletion, not
      before.
- [ ] Every other hostname still serves TLS — the cheap check that catches the step-5 trap.
- [ ] `smoke.sh` has no reference to the retired host and is green.
- [ ] No Keycloak client, Deployment, Service, route, listener or pin for it remains.

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
