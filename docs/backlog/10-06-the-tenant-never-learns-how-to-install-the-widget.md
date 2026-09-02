# The tenant never learns how to install the widget

- **Stage**: 10
- **Status**: done — 2026-09-02 (`ago-chat#150`, `ago-console#87`), completed 2026-09-03 by
  `adr/0092` (`ago-widget#49`, `ago-deploy#114`, `ago-console#89`, `ago-landing#9`). The one box that
  shipped unmet — the snippet itself — needed a public URL that served the widget script, and none
  existed. `#324` carried it and is now closed. See *The box that was not delivered, and how it was*.
- **Found**: 2026-09-02, while preparing a walkthrough checklist for `10-03`. Not from a report; from
  asking what the tenant does *after* signup succeeds.

## The gap

`10-03` ends well: a stranger registers through Keycloak, sets a site name and one embed origin, and
lands in the operator queue exactly as a returning operator would.

**And then there is nothing.** The console never tells her what to put on her website.

Checked rather than assumed, on both sides:

- **Console**: no `<script>` snippet anywhere in `ago-console/src`, and `publicKey` does not appear in
  the source at all — the console never so much as *fetches* the key, let alone renders it. There is a
  `WidgetConfigPage`, but it configures appearance; it does not tell her how to install anything.
- **API**: the only occurrences of `PublicKey` in `Ago.Chat.Api` are on the **visitor** side, where
  `POST /api/v1/visitor-sessions` *consumes* one. **Nothing returns a site's public key to the operator
  who owns that site.**

So the gap is not a missing screen on top of a working endpoint. It is both halves.

## Why it is worth its own item rather than a line in `10-03`

`10-03`'s Done-when is about signup completing and the console routing correctly, and it does that.
This is the next step in the same journey, and it is the step at which a real tenant is otherwise
stuck with a working account and no way to connect it to her shop.

For the first client — a single-person business whose website is one of her three intake channels —
the widget not being installable is the same as the widget not existing.

## Scope

- **An endpoint that returns the caller's own site public key**, gated the way every other
  operator-scoped read is. It is not a secret — it is designed to be embedded in a page anybody can
  view (`adr/0029`, `api-design.md`) — but it belongs to a site, so it is returned to that site's
  operators and not to anybody who asks.
- **A place in the console that shows the snippet, ready to copy**, with the key already in it. Copy
  written for someone who has never seen a `<script>` tag: what it is, where it goes, and how to tell
  it worked.
- **The embed origin she gave at signup is what the snippet must match.** If the two disagree the
  widget fails silently at the browser's origin check, which is unusually hard for a non-technical
  person to diagnose — so the screen should show the origin the site is actually configured with, next
  to the snippet, rather than leaving her to remember what she typed.

## Out of scope

- Verifying the installation from our side (a "we have seen a visitor session from your origin" check).
  Genuinely useful, and a bigger thing — it needs a signal, a screen state and a definition of
  "installed". Named here so it is a deliberate follow-up rather than an oversight.
- Changing how the widget bootstraps (`5-09`) or what the key is (`adr/0029`).
- Multiple origins per site. One is what signup collects today; widening that is its own decision.

## Done when

- [x] An operator can see their own site's public key, copyable, without asking anybody.
- [x] An operator of one site **cannot** read another site's key — proven by test, since this is a new
      read of a tenant-scoped value and the failure mode is silent.
- [x] The configured origin is visible on the same screen.
- [x] The copy is comprehensible to someone who has never edited HTML. Written for a shop owner rather
      than a developer, and it explains *why* the key is not a secret rather than only asserting it.
      Still the author's to judge, as this box always said.
- [x] A complete, copyable snippet, and that snippet pasted onto a page served from the configured
      origin producing a working widget — delivered by `adr/0092` on 2026-09-03, a day after the rest.

## The box that was not delivered, and how it was

The original first box asked for "the public key **and a complete, copyable snippet**". The key
shipped; the snippet did not, and the reason is not that it was hard.

**No public URL serves the widget script.** Checked against the live deployment rather than the code:
`chat.reserve-me.ru/widget.js` returns 404, as do `/ago-chat.js`, `/embed.js` and `/static/widget.js`.
`console.reserve-me.ru/widget.js` returns 200, but a control request to a deliberately nonsense path
returns the identical 3220-byte `text/html` — it is the SPA's catch-all, not a script. The only URL
that really serves the bundle belongs to a **demo shop**, because each demo image carries its own copy.

`ago-landing`'s copy-me snippet has been pointing at one of those 404s the whole time, so anybody who
copied it got a script tag that does not load.

The screen therefore prints **no `<script>` tag at all**, and says so in the tenant's own language.
Composing a URL from `apiBaseUrl` would have handed a tenant a snippet that 404s — worse than having
no screen, and precisely the kind of green-looking breakage this project keeps finding.

### How it was closed

`adr/0092`: a bundle-only image published from `ago-widget`'s own Dockerfile (`--target assets`),
served at `chat-api.reserve-me.ru/widget/` by one prefix rule on the existing API route.

The API's own origin rather than a `widget.`/`cdn.` hostname, and for a reason worth keeping: the
widget bakes its API origin in **at build time**, which is what forced `adr/0091`'s rename into a
three-step migration with a cache-expiry wait. Serving the canonical copy from the API's origin is
the way out — `config.ts` already reads `data-api` with a build-time fallback and already captures
`script.src`, so the widget can eventually derive its API base from where it was loaded. A separate
asset host would have foreclosed that permanently.

That choice also means **the console needed no second config value**: the snippet is composed from
`config.apiBaseUrl`, because the script's origin *is* the API's origin by decision rather than by
coincidence.

Verified on the live deployment, not reasoned about: `200 application/javascript` for the bundle and
its booking module, **`404` for a nonsense path beside them** — the control that separates a real
file server from an SPA catch-all, which is exactly how `console.reserve-me.ru/widget.js` had looked
healthy while serving `index.html`. All three bundles (both demo shops and the canonical copy) are
byte-identical. `ago-deploy/k8s/smoke.sh` now asserts the content *type* rather than a `200`, so the
next silent 404 has something asking about it.

## Open questions

- **Where does it live** — a step at the end of onboarding, a permanent page, or both? A one-time step
  is missed by anyone who closes the tab; a permanent page is one more thing in the navigation. Both is
  probably right and costs little.
- **Does she need it before or after configuring the widget's appearance?** Installing first means she
  sees her own shop with a default-looking widget, which may be the better first impression than
  configuring something she has not yet seen anywhere.
