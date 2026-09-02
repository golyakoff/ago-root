# ADR-0092: The widget script is served from the API origin, under `/widget/`

- **Status**: Accepted
- **Date**: 2026-09-02
- **Decides**: `#324` — nothing serves the widget script at a public URL, which is the last thing
  standing between a tenant and a working install (`10-06` shipped everything except the tag)
- **Related**: `adr/0051` (frontend images take no environment from the build command),
  `adr/0091` (the hostname scheme this URL has to fit), `adr/0058` (the widget's own bundle layout)

## Context

There is no public URL from which a tenant can load the widget. Verified against the live
deployment rather than the code:

- `chat.reserve-me.ru/widget.js` → **404**, as do `/ago-chat.js`, `/embed.js`, `/static/widget.js`.
- `console.reserve-me.ru/widget.js` → 200, but a control request to a deliberately nonsense path
  returns the identical 3220-byte `text/html`. It is the SPA's catch-all, not a script.
- The only origin really serving the bundle is a **demo shop's**, because each demo image bundles
  its own copy (`ago-widget`'s `Dockerfile`, `DEMO_PAGE_DIR`).

`ago-landing`'s copy-me snippet has been handing out `https://chat.reserve-me.ru/widget.js` the whole
time — a 404, and under a filename that does not exist either: the file is **`ago-chat.js`**.

Two constraints that are easy to miss and decide most of this:

1. **The booking module resolves relative to the widget's own `<script src>`** (`ui/moduleLoader.ts`,
   `adr/0058`). Whatever origin serves `ago-chat.js` must also serve
   `ago-chat-module-booking.js` beside it. This is not a single-file problem.
2. **`ago-chat.js` has a fixed filename whose content changes on every deploy** — nothing in
   `build.mjs` is content-hashed. `15-08` already found what that costs: `ago-widget`'s `nginx.conf`
   sends `Cache-Control: no-cache` (revalidate, not "don't cache") for exactly this reason, and any
   new origin has to keep that.

## Decision

**A bundle-only static image, served at `https://chat-api.reserve-me.ru/widget/`.**

So the install snippet becomes:

```html
<script src="https://chat-api.reserve-me.ru/widget/ago-chat.js" data-site="..." async></script>
```

- `ago-widget` publishes a **third image** alongside `ago-demo-shop1`/`ago-demo-shop2` — the same
  build, the same `nginx.conf`, without a demo page. The bundle and its booking chunk, nothing else.
- `ago-deploy` gains a Deployment and Service for it, and **one prefix rule** on the existing
  `chat-api.` route sending `/widget/` there. The API pods never see the request.

### Why the API's own origin rather than a hostname of its own

The obvious alternative is `widget.reserve-me.ru` (or `cdn.`), and it looks tidier: a static asset is
not an API, and `adr/0091` just finished arguing that a host should mean one thing.

It loses on a specific, concrete point. **The widget bakes its API origin in at build time**, and
that single property is what forced `adr/0091`'s rename to be a three-step migration with a
cache-expiry wait in the middle — an already-served bundle cannot be re-pointed by anything we
deploy. Serving the script from the API's own origin is the way out of that, permanently:

`config.ts` already reads `apiBaseUrl = script.dataset["api"] ?? __AGO_DEFAULT_API_BASE_URL__`, and
already captures `scriptUrl: script.src`. Both halves exist. Once the canonical copy is served from
the API origin, the widget can derive its API base **from where it was loaded from**, and the
build-time constant stops being load-bearing for hosted tenants.

A separate asset hostname forecloses that. It would mean the script's origin is deliberately *not*
the API's, so inference could never be correct, and the baked constant stays the only mechanism —
paying `adr/0091`'s migration cost again on the next rename, forever.

Two arguments that turned out **not** to support a separate host, checked rather than assumed:

- *"The API host is rate-limited, assets should not be."* `RateLimitPolicy ago-chat-gateway-per-ip`
  targets the **Gateway**, not a listener or route, so it already applies to every hostname the
  gateway serves — including any new one. A separate host buys nothing here.
- *"Assets need different cache headers."* They do, and they get them: the headers come from the
  bundle-only image's own `nginx.conf`, not from the host it is routed at.

The cost is real and accepted: `chat-api.` now serves one thing that is not the API. It is one prefix
routed to a different Service, and `/widget/` says what it is.

## Follow-up this makes possible, deliberately not done here

Deriving `apiBaseUrl` from `script.src` is a change in `ago-widget`, not in where a file lives, and
it has one trap that has to be handled first: **the demo shops serve their own copy from their own
origin**, so inference there would resolve to `demo-shop1.reserve-me.ru` and break them. They must
pass `data-api` explicitly — two HTML files, one attribute — *before* inference can become the
default. Bundling that into this decision would make a routing change into a behaviour change for
every embedded widget at once.

## Consequences

- One more published image and one more Deployment. Both are copies of shapes that already exist.
- **One URL now serves every tenant**, so one deploy changes the widget on every embedded site at
  once. That is the normal shape for a hosted widget and it is what makes fixes reach customers
  without asking them to do anything — but it also means the widget's blast radius is now every
  tenant simultaneously, which the demo shops avoided by each carrying their own copy. The
  `no-cache` revalidation policy is what keeps that from being a *slow* blast radius as well as a
  wide one.
- The demo shops keep bundling their own copy. They are pinned per image by commit SHA
  (`adr/0051`), which is what makes a demo page reproducible, and pointing them at the shared URL
  would spend that for nothing.
- `ago-landing`'s snippet and `ago-console`'s install screen both get a real URL — the screen is
  built and already prints everything except the tag (`10-06`).

## Alternatives considered

- **Serve it from `Ago.Chat.Api` itself.** No new image, no new Deployment, and the snippet's origin
  is unarguably the API's. Rejected on the image: the API ships on a chiselled .NET base with no
  static content, so the widget bundle would have to be copied into it — coupling the API's image to
  the widget's release cycle, so that shipping a CSS fix in the widget would rebuild and redeploy the
  API. That trade is much worse than one small nginx Deployment.
- **A dedicated `widget.`/`cdn.` hostname.** Above.
- **Point tenants at a demo shop's copy.** It is the only URL that works today, which is exactly why
  it is worth naming and refusing: it would make every customer's site depend on a demo tenant's
  deployment.
- **Content-hashed filenames plus long `max-age`.** The right answer eventually, and orthogonal to
  where the file is served from. It also cannot be adopted without a stable entry point anyway,
  since the snippet a customer pastes must not change when the bundle does.
