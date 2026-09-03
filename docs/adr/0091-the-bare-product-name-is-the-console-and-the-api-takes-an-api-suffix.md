# ADR-0091: The bare product name belongs to the console, the API takes an `-api` suffix

- **Status**: Accepted; **partially superseded by ADR-0093** (2026-09-03) - its premise is a
  console per product, which Stage 22 removes. `office.` becomes the single console and bare
  product names disappear; the `-api` suffix it introduced survives unchanged.
- **Date**: 2026-09-02
- **Amends**: `adr/0026` (its subdomain-to-service map, which named `chat.` as the API and
  `console.` as the console — that mapping is what this reverses)
- **Related**: `adr/0051` (frontend images take no environment from the build command — the reason
  this migration has to be staged rather than simply done), `adr/0027` (AGO Calendar as a second
  product, which is what forced the question)

## Context

`adr/0026` gave out four public names when there was exactly one product, and at that scale the
mapping it chose was unremarkable:

| | |
|---|---|
| `chat.reserve-me.ru` | `Ago.Chat.Api` |
| `console.reserve-me.ru` | `ago-console` |
| `auth.reserve-me.ru` | Keycloak |
| `demo-shop1.`, `demo-shop2.` | the two seeded demo tenants |

`adr/0027` then made AGO Calendar a second product with its own API and its own console, and the
names proposed for it were `calendar.` for the API and `calendar-console.` for the console — by
analogy with chat, where `chat.` is the API.

The author rejected that on sight, and the objection is the whole of this ADR's context: **the two
products would have been named by different rules.** Chat's console is `console.` — a word naming
its *role*. Calendar's would have been `calendar-console.` — the product name plus its role. There
is no rule that yields both. Worse, `console.` is a role word with no product in it at all, which
works only while exactly one product has a console; the moment a second one does, `console.` is
either ambiguous or arbitrarily chat's.

Neither name had been created yet in DNS at the time this was decided (verified, with a negative
control proving there is no wildcard record), so nothing about the calendar's naming was sunk cost.
Chat's was live.

## Decision

**The bare product name is the human-facing surface. The machine-facing surface takes `-api`.**

| Name | Serves | State |
|---|---|---|
| `chat.reserve-me.ru` | `ago-console` — the chat operator console | **reassigned**; today still the API |
| `chat-api.reserve-me.ru` | `Ago.Chat.Api` — REST + both SignalR hubs | new |
| `calendar.reserve-me.ru` | `ago-calendar-console` | new |
| `calendar-api.reserve-me.ru` | `Ago.Calendar.Api` | new |
| `auth.reserve-me.ru` | Keycloak | unchanged |
| `demo-shop1.`, `demo-shop2.` | the two seeded demo tenants | unchanged |
| `grafana.reserve-me.ru` | Grafana | unchanged |
| `reserve-me.ru` (apex) | `ago-landing` | unchanged |
| `console.reserve-me.ru` | `ago-console` | **to be deleted** once `chat.` serves it |

That is the whole list — it is the certificate's SAN list (`k8s/overlays/demo/tls.yaml`), and the
rule above only governs the four product names. `auth.`, `grafana.` and the apex are not products
and keep the names they have.

The rule generalises to a third product without another argument, which is the property `adr/0026`'s
map did not have: the console for product *X* is `X.`, its API is `X-api.`, and no name has to be
invented for a role.

It also puts the better name on the surface a human types. `console.reserve-me.ru` is a word from
the system's own vocabulary — a tenant does not think of themselves as opening a console, they think
of opening AGO Chat. `CLAUDE.md`'s own copy rule ("name things by what people recognize, not how the
system is built") applies to hostnames as much as to buttons, and `chat.reserve-me.ru` is the name a
customer would guess.

## Why the chat half has to be staged, and the calendar half does not

The calendar's two names are new, point at nothing today, and can be created and used in one step.

`chat.` cannot, because **it is a live name whose meaning changes**, and one class of consumer
cannot be re-pointed after the fact:

> The widget bundle bakes its API origin in **at build time** (`adr/0051`, and `ago-widget`'s
> `Dockerfile` `ARG AGO_API_BASE_URL`). A visitor's browser holds a cached copy that calls whatever
> origin it was compiled with. There is no configuration that reaches an already-served widget, and
> no deploy that changes its mind.

So flipping `chat.` from the API to the console in one step would break every embedded widget still
holding a cached bundle — and the widget is the one artifact whose lifetime is controlled by
somebody else's browser cache, not by the deployment.

The migration is therefore three ordered steps, and the ordering is load-bearing:

1. **The API answers on both names.** `ago-deploy`'s Gateway gains an `https-chat-api` listener and
   a second hostname on the chat API's route, with `chat-api.` added to the certificate's SAN list.
   `chat.` keeps working, unchanged, for everyone.
2. **Every consumer moves to `chat-api.`** and is verified there — the widget's build default, the
   console's `.env.production`, the demo images, `smoke.sh`, the Keycloak client's redirect URIs.
   This step is where the cached-bundle problem is actually paid off: it does not end when the
   configuration changes, it ends when the old bundles have aged out.
3. **Only then** does `chat.` change meaning, and `console.` is deleted afterwards, not
   simultaneously — so a bookmark or a stale link has one release in which both work.

Merging step 2's changes ahead of step 1's deployment is safe and does not need coordinating:
nothing is deployed by merging, and `ago-deploy` pins images by commit SHA rather than following a
tag (`adr/0047`).

## Consequences

- The certificate's SAN list grows by three names. It is one multi-SAN certificate, so this is one
  more issuance, not three.
- Keycloak's `ago-console` client needs `https://chat.reserve-me.ru/*` added to its redirect URIs
  **before** step 3 and its `console.` entries removed after — a realm change, so
  `docs/runbooks/realm-operations.md` applies.
- `docs/runbooks/public-deploy.md` records the `8-01` deployment as it was actually performed, with
  real command output. It is a transcript, not an instruction sheet, and it is **not** being
  find-and-replaced: rewriting the hostnames in a record of what was run would make it a false
  record. It becomes wrong at step 3, and is corrected then.
- Closed backlog items and earlier ADRs keep the names they were written with, for the same reason.
- **This ADR does not give the widget script a home.** `ago-landing`'s copy-me snippet points at
  `https://chat.reserve-me.ru/widget.js`, which returns 404 and always has; the only origin actually
  serving the bundle is a demo shop's own, because each demo image carries its own copy. That is a
  real defect, it is independent of this rename, and it is `ago-root#324`. It is called out here
  because the obvious reading of this table — "the API is at `chat-api.`, so the widget must be at
  `chat-api./widget.js`" — is an assumption, not a decision, and #324 is where it gets made.

## Alternatives considered

- **Leave chat alone and name the calendar `calendar-api.`/`calendar-console.`.** Cheapest: no live
  name changes meaning, no staging, no certificate churn. Rejected because it buys that cheapness by
  making the naming rule unstateable — every future product would have to be told which of two
  precedents it follows, and the answer would be "whichever product it resembles", which is not a
  rule. The cost of fixing this is strictly lowest now, with one product deployed and one console
  with a handful of consumers; it rises with every name added.
- **`api.chat.reserve-me.ru` — a second label instead of a suffix.** Reads better, and nests the way
  the system is actually shaped. Rejected on TLS: `*.reserve-me.ru` covers one label, so
  `api.chat.` needs either its own wildcard or its own SAN entry per product, and the DNS provider's
  wildcard record does not answer for it. The suffix form stays inside the single flat namespace
  everything else already lives in.
- **Path-based routing on one host** (`reserve-me.ru/chat`, `/chat/api`) — already rejected in
  `adr/0026` for its own reasons, and nothing here revisits them.
- **Flip `chat.` in one step and accept the breakage.** Rejected on the widget: the broken party is
  a tenant's visitors on a tenant's site, the breakage is invisible from our side, and the recovery
  requires that tenant to do nothing at all except wait for a cache to expire. That is not an
  acceptable failure to choose deliberately when the alternative is one extra listener.
