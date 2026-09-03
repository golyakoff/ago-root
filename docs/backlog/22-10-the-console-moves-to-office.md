# The console moves to `office.reserve-me.ru`

- **Stage**: 22
- **Status**: done (2026-09-03)
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

- [x] An operator signs in at `office.reserve-me.ru` and holds a hub connection from that origin. —
      the author did, and went straight online. **This is the box the whole item was waiting on**, and
      the one no layer beneath it could substitute for.
- [x] The certificate is `Ready` with `office.` in it and every other hostname still serves TLS.
- [x] `chat.` is retired or redirects, deliberately, and its A-record dies **after** its SAN entry. —
      retired outright rather than redirected, and the reason is worth stating: it had been the
      console for about ten hours. A bookmark risk that small does not buy a name kept alive in DNS
      and in a certificate forever. The A-record went last, after the certificate had re-issued
      without the name.
- [x] Nothing in the repositories, the manifests, the landing page or `smoke.sh` still points an
      operator at `chat.`. — see the Outcome: two of those were found only by rendering.
- [x] `adr/0091`'s scheme is amended to say what replaced it. — `adr/0093`, and `0091` carries a
      partially-superseded note with its original text untouched.

## Outcome

Done 2026-09-03, in the order the item wrote down, and the order turned out not to be decorative.

**The landing page's login link moved first**, before anything was removed. A link is the one part of
a hostname move visible to somebody who is not watching, and pointing it at a name about to be deleted
— even for one deploy — sends whoever clicks it nowhere.

**Two live references survived a source-level search and appeared only in `kubectl kustomize` output**,
where comments are gone and every remaining string is real:

- **Three billing return URLs** — `api.yaml`, `webhooks.yaml`, `worker.yaml` — all pointing at
  `https://chat.reserve-me.ru/settings/billing`. A customer finishing a YooKassa payment would have
  landed on a deleted hostname.
- **The Keycloak realm import** still provisioned `ago-console` against `chat.`. Harmless on this
  realm, since `--import-realm` is skip-if-exists — and it would have built the *next* cluster
  pointing at a name that does not exist.

Render count after: `chat.` **0**, `office.` **9**.

**The A-record was deleted last, and the reason held.** With the name already out of the SAN, the next
renewal will not request an HTTP-01 challenge for it. Reversed, one failed authorization takes the
whole certificate down and every other hostname loses TLS with it — which nearly happened with
`grafana.` earlier the same day, caught only by checking the SAN *after* the record was gone.

`smoke.sh` after: **40 passed, 0 failed**, with the operator-origin check now made against `office.`
because that is the origin worth checking.

### The failure this item cost, and what it produced

Signing in the first time failed with `Sign-in failed: Failed to fetch`. Sign-in had **succeeded**;
what failed was the first API call, refused by CORS because `office.` was in no site's
`allowed_origins`. That layer lives in the **database**, not in a manifest — so the certificate, the
listener, the route, the Keycloak client and the hub origin were each verified while the one that
mattered was not, and `smoke.sh` reported 43 green throughout.

Two items came out of that: `15-14` (the suite cannot see this layer at all) and `11-17` (the console
names the wrong step, sending whoever reads it to the wrong place — as it sent both of us).
