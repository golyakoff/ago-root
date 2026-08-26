# ADR-0064: AGO Calendar's console is its own repository; its booking UI is not

- **Status**: Accepted
- **Date**: 2026-08-26
- **Stage**: 20 (`backlog/20-06-console-and-booking-widget.md`)
- **Related**: `adr/0012` (the platform is a package, not a folder), `adr/0023` (React for
  `ago-console` — reused unchanged, *not* re-litigated here), `adr/0027` (two products, not one),
  `adr/0051` (a frontend image takes no environment from its build command), `adr/0061` (a message
  can carry structure AGO Chat does not understand), `adr/0065` (AGO Chat carries a module's steps
  without understanding them — decided separately the same day, and arriving at the same step shape
  from the other direction), `reviews/2026-08-26-platform-boundary.md`

## Context

`20-06` gives AGO Calendar its two frontends, and each of them raises the same question with
opposite answers. The item left one of them open and had the other settled for it.

**The embed was settled on 2026-08-26**, on product grounds, by the third pass of the boundary
review: booking must be reachable from Telegram, MAX and SMS as well as from a widget, and some
shops will run with no widget at all — so a booking-only embed would build the one shape the product
model rules out. One script tag; booking is reached through it. This ADR applies that rather than
re-deciding it, and records what applying it actually cost.

**The console was left to this item.** The forces:

- `repositories.md` states the test in one line: *"Only when the thing versions or deploys
  independently."*
- `ago-console` is AGO Chat's static bundle. It has its own GHCR image, its own CI, and `deploy.sh`
  moves it independently of the API (`adr/0051`, `15-07`).
- A calendar console tracks `Ago.Calendar.Api`'s contract, which moves on `ago-calendar`'s schedule.
- The review measured the widget/console duplication that made the *embed* decision easy — the
  ordering, backoff and dedup primitives, 100% identical across two repositories. **That argument
  does not transfer to the console**, and noticing why is what made this decision straightforward:
  AGO Calendar has no realtime client at all. There is no SignalR connection, no sequence cursor and
  no reconnect backoff here, so the thing that was triplicating is not present.
- What *would* be shared is the OIDC plumbing and a design system.
- The one genuine argument for combining is a single "AGO operator hub" login. `adr/0027` names that
  as a real, deferred gap, and `20-06` puts it out of scope.

## Decision

**AGO Calendar's console is a new repository, `ago-calendar-console`.** React + Vite + TypeScript,
`adr/0023` reused unchanged.

**AGO Calendar's booking UI is a module inside `ago-widget` (`src/booking/`), reached from the chat
widget's own panel.** No second repository, no second package, no second script tag and no second
floating launcher. A shop that bought only chat gets a byte-identical panel and makes no request to
a product it does not have — enforced by a test, not by intent.

Three properties fall out of the second half and are worth stating as commitments rather than as
implementation details:

1. **The booking flow's view model is `adr/0061`'s message contract**, written on the client side: a
   kind, an opaque payload, a mandatory prose body, and a list of labelled actions
   (`ago-widget/src/booking/steps.ts`). The browser panel is one renderer of it; an eleven-line text
   renderer that reads **no field of the payload** is another, and a test drives an entire booking to
   completion through that renderer using only digits. That is `20-06`'s own constraint — *"whatever
   the slot picker renders must be expressible as conversation content a channel with no UI can also
   carry"* — turned into something that can fail.
2. **AGO Calendar is named in exactly one file** (`booking/calendarClient.ts`). Everything above it —
   the step model, the flow, the panel — names no product. When `21-01` drives the same interaction
   through a conversation instead of over HTTP, that file is what it replaces.
3. **The tenant's calendar key comes off the shop's own script tag** (`data-booking`,
   `data-booking-api`), never from AGO Chat's widget-config response. The obvious alternative would
   put AGO Calendar's identifier inside `Ago.Chat.Domain.WidgetConfig` — one product's domain holding
   another's — which is exactly the shape `adr/0061` refuses on the server side.

## Consequences

- **The OIDC plumbing is duplicated, and this is the second such duplication the project has
  knowingly accepted.** `adr/0027` accepted the first (a copied claims transformation, which `20-06`
  finally made real). `ago-calendar-console/src/auth/` is `ago-console/src/auth/` with a different
  client id. Roughly a hundred lines, structurally identical, that will drift. Stated because a
  reader who finds it should find it already recorded rather than as evidence nobody looked.
- **Two consoles means two Keycloak clients and two redirect-URI allowlists.** That is a cost and
  also a property: one shared client would let either bundle complete the other's login.
- **A shop running both products has two operator consoles at two URLs, and signs in twice.** The
  deferred gap in `adr/0027`, now visible to a user rather than only to a reader. If it turns out to
  be the thing customers complain about, the fix is a hub in front of both, not a merge of the two —
  and that would be its own ADR.
- **`ago-calendar-console` ships with no `.env.production` and no image-publishing CI job**, because
  AGO Calendar has no deployment. Committing either would mean inventing an endpoint. The Dockerfile
  and the workflow both say so at the point where somebody would otherwise add one, including why
  `adr/0051` forbids solving it with a build argument.
- **The widget grew by 2.7 KB gzipped** — 22.2 KB to 24.9 KB against a 45 KB budget. `20-06` asked
  for this number specifically, because a lazily-loaded module was the pre-agreed answer if the
  budget were threatened. It was not, so no split was built. If a later booking feature changes that,
  the split is the fix and the budget is not.
- **The widget now issues cross-origin requests to a second API.** Both of AGO Calendar's CORS layers
  had to exist before the module could work at all, which is why `20-06` carries them.
- **`21-01` inherits a step model rather than a screen.** What it has to build is a producer of these
  steps and an answer to "who parses the intent" — which `adr/0061` deliberately left open and this
  ADR does not touch.

## Alternatives considered

- **A new area inside `ago-console`.** The cheapest option, and the only one that would have made a
  single sign-in trivially possible. Rejected on `repositories.md`'s stated test: one bundle for two
  products means a calendar change rebuilding and redeploying AGO Chat's console, and a build in
  which either product's code can import the other's — the coupling the repository split exists to
  make impossible rather than merely discouraged. The single-sign-in benefit is real and is recorded
  above as a cost of this decision rather than dismissed.
- **A new app inside `ago-console`'s repository** (a second Vite entry point, one repository, two
  bundles). Tempting, because it removes the duplication above while keeping the artifacts separate.
  Rejected because it keeps the part that matters — one release cadence, one CI, one set of reviewers
  for two products' frontends — while adding a second build to configure. It is the answer if the
  duplication ever becomes painful *and* the deploy independence stops mattering; today only the
  first half is true.
- **A shared npm package for the OIDC plumbing**, consumed by both consoles. This is the honest fix
  for the duplication, and it is what the boundary review recommends for the *protocol* primitives.
  Not done here, and the reason is that it would be a third repository to version and publish for a
  hundred lines with two consumers — `repositories.md`'s own "a new adapter does not qualify"
  reasoning. It becomes right when there is a third consumer or when the copies have actually
  drifted; recorded so that a later item can point at this paragraph rather than re-deriving it.
- **A separate `ago-calendar-widget` repository or package.** Ruled out by the boundary review before
  this item ran, on the product grounds summarised in Context. Listed because a reader looking for it
  should find the reason, not silence.
- **Serving the booking module from AGO Chat's own widget config** (so the shop pastes one attribute
  instead of two). Rejected: it puts AGO Calendar's tenant key inside `Ago.Chat.Domain`, which is a
  product-to-product dependency through a data model — the failure mode `adr/0061` names as "the easy
  path" and exists to refuse.
- **A booking-specific card renderer in the widget** — a real calendar grid, with the widget parsing
  AGO Calendar's payload. Rejected, and this is the load-bearing rejection: a renderer that reads the
  payload is a renderer only a browser can have, and `21-01` has to work over plain text. The labelled
  actions cost the picker some polish and buy it a second channel.
