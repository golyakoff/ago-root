# Widget bootstrap: apply per-site configuration

- **Stage**: 11
- **Status**: ready
- **Depends on**: `11-01-widget-config-data-model-and-api.md` (the handshake response field this item
  reads) — not on `11-02`, since this item can be verified against `11-01`'s real API directly (a curl
  `PUT`, matching how `5-01`'s CORS mechanism was verifiable before any console UI existed to drive it)

## Goal

The widget bootstrap in `ago-widget` reads the primary color and launcher position `11-01` added to
`POST /api/v1/visitor-sessions`'s response and applies them to what it renders — no rebuild, no
redeploy, no per-site bundle. This is the last piece of Stage 11's own done-when bar: it is what makes
a console-side change in `11-02` actually visible on a real embedded page.

## Context to read first

**`.claude/skills/embeddable-widget/SKILL.md` in full** — the same constraint list `5-09`/`5-10` were
built against: Shadow DOM isolation, bundle-size ceiling enforced in CI, "every entry point wrapped so
an internal failure degrades to no-widget, never a broken host page." This item's own failure mode
specifically: a missing, malformed, or out-of-range config value from the handshake response must fall
back to the widget's own built-in default silently, never throw. `docs/backlog/5-09-widget-bootstrap-and-messaging.md` —
the exact bootstrap sequence this item extends (`data-site` → `POST /api/v1/visitor-sessions` → mount
Shadow DOM root → render), and the current bundle-size number (18.4 KB gzipped at `5-09`, 19.9 KB after
`5-10`, against a 45 KB budget) this item must re-measure against. `11-01`'s exact response field
shapes and its ADR's stated limitation (config is read once, at bootstrap; an already-open widget does
not update live) — this item is where that limitation becomes a real, observable fact about the shipped
bundle, not just written down.

## Scope

- Bootstrap reads the new field(s) from the handshake response already fetched at `data-site` time (no
  second network call — the response already carries this by the time `11-01` ships).
- **Position**: the Shadow DOM host element's own placement (however `5-09` currently anchors it —
  state the mechanism once found, e.g. a fixed-position container appended to `document.body`) reads
  the position value and mounts bottom-left or bottom-right accordingly. An unrecognised or missing
  value falls back to the widget's own existing default placement, not an error.
- **Primary color**: applied as a CSS custom property on the shadow root (or the host element, inherited
  into the shadow tree — state which), consumed by the widget's own internal stylesheet for whatever
  currently uses a hardcoded accent color (launcher button, header, send button). A missing/malformed
  value falls back to the widget's own existing built-in color, matching the "courtesy validation,
  never trust the wire value blindly" posture the widget already takes toward file-size limits (`5-10`).
- Re-measure the bundle-size budget with this feature included, matching `5-10`'s own precedent
  ("Bundle-size budget is re-measured with this feature included and still enforced in CI") — state the
  new number in `ago-widget/README.md`.

## Out of scope

- Any field beyond primary color and position (`11-01`'s own scope) — if `11-04` resolves to more
  fields later, this item's own follow-up work grows to match, not guessed at here.
- A live-update channel that changes an already-open widget's appearance without a page reload — `11-01`'s
  ADR already states why this item does not build one; a visitor who has the widget open across a config
  change sees the old appearance until their next page load, which re-runs the bootstrap handshake fresh.
- Any change to the connection/reconnect/messaging protocol layer `5-09` built — this item only changes
  what bootstrap does with one more field in a response it already fetches.

## Done when

- [ ] Manually verified against the local cluster, the same hostile demo host page `5-09`/`5-10` used: a
      site's widget config is changed via `11-01`'s real API (curl or the console once `11-02` exists),
      and a **fresh page load** of the demo host page shows the widget in the new position with the new
      accent color — proving the field actually reaches rendered output, not just that it round-trips
      through a DTO.
- [ ] A site with no widget config set (the pre-`11-01` default, or a fresh site that never called
      `PUT .../widget-config`) renders with the widget's original built-in appearance — no visible
      regression for every site that predates this item.
- [ ] A deliberately malformed value from the handshake response (simulated, e.g. via a local proxy or a
      unit test against the parsing function directly) falls back to the built-in default and never
      throws an uncaught exception on the host page — proven the same
      `window.onerror`/`unhandledrejection`-listener way `5-09`'s own internal-error done-when item was
      proven.
- [ ] Bundle size re-measured and stated as a real number in `ago-widget/README.md`; CI's existing
      budget check still passes.
- [ ] `.claude/skills/embeddable-widget/SKILL.md`'s Bootstrap section — currently describing this as
      already true ("The handshake returns the site's widget settings... ") — gets a "Shipped in
      `11-03`" note now that the sentence is actually accurate end to end, matching how every other
      "documented, not yet wired" note in this project gets closed out once real.

## Open questions

None for the scope shipped here — the mechanism (read an already-fetched response field, apply as a CSS
custom property and a placement class, fall back silently on anything malformed) follows directly from
`11-01`'s contract and the widget skill's own existing error-handling rules. `11-04`'s open question does
not block this item; it only grows this item's own future scope if it resolves toward more fields.
