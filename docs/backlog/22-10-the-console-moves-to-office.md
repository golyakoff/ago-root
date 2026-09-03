# The console moves to `office.reserve-me.ru`

- **Stage**: 22
- **Status**: ready
- **Depends on**: `22-01` (for the naming decision it records)
- **Decided**: 2026-09-03 by the author; A-record created the same day, deliberately early, because
  adding a name to the certificate needs it to resolve first.

## Why a new name rather than keeping `chat.`

`adr/0091` settled a scheme where the **bare product name is that product's console** and `-api` is
its API — so `chat.` became the chat console only this morning. Stage 22 removes the premise: there is
no per-product console any more, so "the bare product name is the console" names a thing that no
longer exists, and `chat.` would be a console that administers the calendar too.

`office.` is not a product. That is the whole point of it, and it is why this supersedes part of
`adr/0091` rather than adjusting it.

**The scheme after this lands:**

| | |
|---|---|
| `reserve-me.ru` | the landing page |
| `office.reserve-me.ru` | **the console — one, for every product** |
| `chat-api.reserve-me.ru` | AGO Chat's API, and the widget bundle it serves |
| `calendar-api.reserve-me.ru` | AGO Calendar's API |
| `auth.reserve-me.ru` | Keycloak |
| `demo-shop1/2.reserve-me.ru` | the demo stands |

Bare product names disappear entirely, which is a simpler rule than the one it replaces: **a hostname
is either the console, one product's API, or a thing that is not ours to name.**

## Why this lands before the calendar screens move

It is independent of them, and doing both at once means not knowing which one broke. A hostname move
is small and provable on its own; `22-06` then merges screens into a name that has already settled.

## The order, which is not interchangeable

1. **The name resolves first.** Checked from the node, not from a workstation — this project has a
   local proxy that answers for the real domain and will lie about it.
2. **Add `office.` to the certificate SAN.** Adding needs HTTP-01 to succeed for the new name, which
   is why step 1 is a gate rather than a courtesy. The certificate re-issues once; the names already
   working keep working through it, because cert-manager does not replay authorizations that passed.
3. **Listener, route, and Keycloak.** The `ago-console` client gains `https://office.reserve-me.ru/*`
   in `redirectUris` and the origin in `webOrigins`. `--import-realm` is skip-if-exists, so this is
   `kcadm` by hand on the live realm; the file edit is for the next cluster.
4. **Both origins accepted before either is retired.** `Console__AllowedOrigins` on `ago-chat-api`
   takes `office.` *in addition to* `chat.` — a single-value switch breaks the old name the instant
   the new one works, with no overlap to verify in. `5-18` is the item that exists because this was
   got wrong once.
5. **Verify a real sign-in at `office.`** — an operator holding a hub connection from that origin,
   not a 200 from a static bundle. `20-20` shipped a check that fetched a SPA while its API was
   crash-looping.
6. **Then retire `chat.`**: route, listener, SAN, and **only then** the A-record. Reversing those
   last two fails the next HTTP-01 renewal for a name still in the SAN, and one failed authorization
   fails the whole certificate — every other hostname loses TLS with it. Nearly happened with
   `grafana.` on 2026-09-03.
7. **The landing page's operator-login link** moves with it, along with any `chat.` in documentation,
   `smoke.sh`, and the demo pages. It was moved to `chat.` this morning; it moves again.

**Consider a redirect rather than a deletion for `chat.`** — operators have it bookmarked, and
`http-to-https-redirect` is an existing route this repository already knows how to write. If it is
deleted instead, say so deliberately; a bookmark that resolves to nothing is a support conversation.

## Done when

- [ ] An operator signs in at `office.reserve-me.ru` and holds a hub connection from that origin.
- [ ] The certificate is `Ready` with `office.` in it and every other hostname still serves TLS.
- [ ] `chat.` is retired or redirects, deliberately, and its A-record dies **after** its SAN entry.
- [ ] Nothing in the repositories, the manifests, the landing page or `smoke.sh` still points an
      operator at `chat.`.
- [ ] `adr/0091`'s scheme is amended to say what replaced it.
