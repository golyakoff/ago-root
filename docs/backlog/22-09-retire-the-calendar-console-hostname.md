# Retire `calendar.` — route, listener, certificate, Keycloak client, DNS

- **Stage**: 22
- **Status**: ready
- **Depends on**: `22-06` (hard — nothing here happens until the merged console is proven live)

## What retires, and what stays

| | |
|---|---|
| retires | `calendar.reserve-me.ru` — the calendar console's hostname |
| retires | its `HTTPRoute`, its `https-calendar-console` Gateway listener, its name in the certificate SAN, its A-record |
| retires | the `ago-calendar-console` Keycloak client |
| retires | the `ago-calendar-console` Deployment, Service and image pin |
| **stays** | `calendar-api.reserve-me.ru` — **the console merges, the API does not** |

## The order, and it is not interchangeable

This is the reverse of `adr/0091`'s migration and the same traps apply, in mirror image. Two of them
have already cost this project something specific.

1. **Merged console proven at `chat.`** — a real sign-in reaching a calendar screen. Not "it serves
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

## Done when

- [ ] `calendar.reserve-me.ru` resolves to nothing and serves nothing.
- [ ] The certificate is `Ready` with the remaining names, checked **after** the DNS deletion, not
      before.
- [ ] Every other hostname still serves TLS — the cheap check that catches the step-5 trap.
- [ ] `smoke.sh` has no reference to the retired host and is green.
- [ ] No Keycloak client, Deployment, Service, route, listener or pin for it remains.
