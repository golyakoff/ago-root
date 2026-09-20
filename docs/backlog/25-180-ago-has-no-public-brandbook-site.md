# 25-180 · AGO has no public brandbook site

- **Stage**: 25
- **Status**: done — `ago-brandbook#1` (`f137ab0`→`981c9b6` on `main`) + `ago-deploy#235`/`#236`
  (`1ca4a06`, `0adef68`). Independently re-verified by the managing session before merging (icon files
  byte-identical to the `25-172` sources, `Dockerfile`/CI diffed against `ago-landing`'s own templates,
  local `docker build` + rendered page viewed in a browser, `kubectl kustomize` local render clean) —
  and then actually deployed and checked live: DNS confirmed resolving to the real node, applied via
  `apply-demo.sh`, the shared `ago-public-tls` certificate reissued with `brandbook.reserve-me.ru`
  added and every pre-existing hostname still serving correctly, `curl https://brandbook.reserve-me.ru/
  version.json` returns the deployed commit, `check-manifest-drift.sh` clean.
- **Depends on**: `25-172` (the five real brand icon files this site would showcase - reuse them
  verbatim, do not re-derive)
- **Found**: 2026-09-20, the author's own request: a public brand-identity reference site, built as its
  own deployable unit with its own subdomain, explicitly asked for as two parts - build, then roll out
  with a live check that it actually answers.

## What is actually true today

AGO's visual identity exists, but only scattered across the codebases that happen to use it: `ago-landing/
styles.css`'s own `--blue`/`--violet` tokens (which `docs/backlog/11-05-console-design-foundation.md`
already took the console's own colour/type system from - `repositories.md`'s own record of this),
`ago-console/src/design/tokens.css`'s fuller token set, and, as of `25-172`, five real channel-brand icon
files (`telegram.svg`/`whatsapp.svg`/`vk.svg`/`max.svg`/`avito.svg`). There is no single page that shows
what AGO's own identity actually is - a designer, a future hire, or the author's own future self has
nowhere to look.

## Goal

A public, standalone site at its own subdomain, documenting AGO's own visual identity: color tokens,
type scale, the five real channel icons, and whatever else the author wants on it (a logo mark, voice/
tone notes, component patterns) - scope that content list with the author when building, this item does
not prescribe it exhaustively.

## The two parts, as the author asked

**Part 1 - build.** A new site, in its own new repository (`ago-brandbook`, following `ago-landing`'s
own precedent as "added later than the five... recorded... as of" - `repositories.md`'s own pattern for
when a new public-facing surface earns its own repo rather than folding into an existing one).

- **Engine: the author left this open ("можешь использовать какой-то движок") - default to
  `ago-landing`'s own proven shape** (hand-authored static HTML/CSS/JS, no build step, no bundler,
  no framework - that repository's own `Dockerfile` header states the reasoning: "the easiest of the
  four frontends to make honest... there is no environment input here at all") **unless the author
  prefers a real static-site generator once scoping the actual content shows it's worth the added build
  step.** Either way, the deployed artifact is still a static file tree served by nginx - the choice only
  affects how that tree gets authored.
- Reuse `25-172`'s five icon files and the design tokens already established in `ago-console`/
  `ago-landing` rather than re-deriving colors or re-sourcing icons.

**Part 2 - roll out, with a final live check.** Package and deploy exactly the way `ago-landing`,
`ago-demo-shop1`/`2`, and the console bundle already do (`docs/architecture/repositories.md`'s "four
static bundles publish the same way", `15-07`/`adr/0051`):

- A `Dockerfile` mirroring `ago-landing`'s own exactly: `nginx:1.31-alpine-slim`, `apk update && apk
  upgrade --no-cache` for the same continuously-patched-base reasoning that file's own header states,
  explicit named `COPY` lines (never `COPY .`), a `version.json` baked from `GIT_COMMIT` and served at
  `/version.json` - the same one-question-one-answer contract `smoke.sh`/`deploy.sh` already rely on for
  every other frontend.
- CI publishing `ghcr.io/golyakoff/ago-brandbook:<40-char commit SHA>` on `main`, the identical shape
  `ago-landing`'s own CI already has (that repository "had no workflow at all before" its own item added
  one - check whether this new repo needs the same bootstrap).
- A new `k8s/overlays/demo/brandbook-static.yaml` (`ago-deploy`), copying `landing-static.yaml`'s own
  Deployment/Service shape verbatim (same resource requests/limits, same security context, same
  readiness/liveness probes against `/`).
- **A new subdomain and its own Gateway listener + HTTPRoute + TLS cert entry** - `gateway.yaml`'s
  existing per-hostname listener pattern (each of `demo-shop1.`/`demo-shop2.`/`chat-api.`/etc. is its own
  explicit `https-<name>` listener block, not routed through the existing `*.reserve-me.ru` wildcard
  listener alone) and `tls.yaml`'s `dnsNames` list (a real Let's Encrypt validation, not instant) both
  need a new entry for whatever hostname is chosen.
- **Decided**: `brandbook.reserve-me.ru` - registered by the author at reg.ru, 2026-09-20. Verify the
  record has actually propagated (`dig brandbook.reserve-me.ru` or equivalent) before adding it to
  `tls.yaml`'s `dnsNames` - a certificate request against a name that doesn't resolve yet just fails
  the validation rather than silently waiting for it.
- **Done only once actually verified live** - per the author's own explicit "финальная проверка - что
  вживую он доступен": `curl https://<the-chosen-hostname>/version.json` returns the deployed commit,
  the same real, bounded check `smoke.sh` already performs for every other public hostname - not merely
  "the manifest applied without error."

## Out of scope

- Prescribing the brandbook's exact page content/IA - a real design decision for whoever builds it,
  informed by what identity assets actually exist today (see Goal).
- Any change to `ago-landing`/`ago-console`'s own existing token files - this item documents them, it
  does not move or rename anything they already own.
- A CMS, a build pipeline beyond what "Part 1"'s chosen engine needs, or any dynamic/backend behavior -
  this is a static reference site, the same shape every other demo-overlay frontend already is.

## Done when

- [x] The site exists in its own repository, reviewable and buildable independently of every other repo.
      — `github.com/golyakoff/ago-brandbook`.
- [x] `brandbook.reserve-me.ru`'s DNS record is confirmed resolving before it is added anywhere in
      `ago-deploy`. — confirmed resolving to the same IP as the known-live `reserve-me.ru` apex before
      `tls.yaml`/`gateway.yaml` were applied.
- [x] The site is deployed on the demo overlay, reachable at `https://brandbook.reserve-me.ru` with a
      valid TLS certificate. — `apply-demo.sh` run against the real cluster; `ago-public-tls` reissued
      with `brandbook.reserve-me.ru` in its SAN list, every pre-existing hostname on that same
      certificate re-checked live and still serving correctly.
- [x] `curl https://<hostname>/version.json` returns the actually-deployed commit SHA, checked live
      against the real deployment - not asserted from the manifest. — returns
      `{"app":"ago-brandbook","commit":"981c9b6fcf34cce99d4ce5464c6469759b9532fe"}` live.
- [x] `k8s/overlays/demo/kustomization.yaml`'s `newTag` for the new image is set to the deployed commit.
      — `ago-deploy#236`, set to `981c9b6...` once `ago-brandbook`'s own CI published it;
      `check-manifest-drift.sh` confirmed clean afterward.
