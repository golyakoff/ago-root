# Static frontends serve no Cache-Control header at all

- **Stage**: 15
- **Status**: done (2026-08-31, `ago-widget#41`, `ago-console#74`, `ago-landing#7`+`#8`,
  `ago-deploy#102`, all merged and deployed to the demo)
- **Depends on**: `15-07-publish-the-frontends-too.md` (done) — that item made every frontend image a
  truthful, SHA-tagged artifact; this item is the gap it left standing, that *identity* and
  *freshness in a browser's own cache* are two different questions

## Goal

A deploy that changes `ago-widget`, `ago-console`, or `ago-landing` reaches every visitor's browser
within one reload, not "eventually, once whatever cache lifetime nginx's own defaults picked has
expired." Today none of the four static-frontend images (`ago-console`, `ago-demo-shop1`,
`ago-demo-shop2`, `ago-landing`) sets `Cache-Control` on anything they serve — confirmed live, not
assumed: `curl -i https://demo-shop1.reserve-me.ru/ago-chat.js` returns `ETag`/`Last-Modified` and no
`Cache-Control` at all, which is plain nginx's own default for a static file with no directive
overriding it.

## Why this was found, and why it is more than a tidiness gap

Found live on 2026-08-30 while fixing a critical, unrelated bug (`ago-widget#40` — the
`SendMessageAsync`/`SendStructuredMessageAsync` hub arity mismatch that made every visitor message fail
to send). After that fix was built, published, and deployed — `deploy.sh`'s own `smoke.sh` run 25/25
green, server confirmed serving the corrected commit — a browser that had loaded the demo page *before*
the fix kept running the *old, broken* `ago-chat.js` after a normal reload, and after an explicit
hard-reload (`Ctrl+Shift+R`). The only way to observe the fix working live was to bypass the browser's
own HTTP cache programmatically (`fetch(url, { cache: "no-store" })`) and re-inject the bundle by hand.

That is the concrete cost of the gap: **a fixed, deployed, verified-on-the-server bug can still be live
for an already-cached visitor for an unknown, uncontrolled length of time**, bounded only by Chrome's
own heuristic-caching guess (roughly a fraction of the file's `Last-Modified`-to-`Date` age, per RFC
9111 §4.2.2 — not a number this project sets or can rely on), because no explicit directive tells the
browser otherwise. For a security fix, not just a UX bug, this gap would mean an unknown fraction of
visitors keep running vulnerable client code after the fix has already shipped.

## Context to read first

`15-07`'s own file and `adr/0051` — the sibling decision this item completes the other half of:
identity (which commit is running) was solved there; this item solves currency (how quickly a fixed
commit actually reaches a browser). `ago-console/nginx.conf` and `ago-widget`/`ago-landing`'s
Dockerfiles — all three currently rely on `nginx:*-alpine-slim`'s stock config with **no**
`Cache-Control`/`Expires` directive anywhere, confirmed by reading each, not assumed to be uniform.

## What's actually different between the four images, and why one policy does not fit all

- **`ago-widget`'s two demo-shop images and `ago-landing`**: every file they serve (`ago-chat.js`,
  `demo-boot.js`, `ago-chat-module-booking.js`, `index.html`, `version.json`) has a **fixed filename**
  that changes *content* on every deploy — there is no cache-busting-by-filename anywhere in this
  build. The only correct policy for a fixed-filename file that changes content is "always revalidate
  before trusting a cached copy" — `Cache-Control: no-cache` (which, despite the name, still allows a
  cached copy to be *used* after a cheap conditional revalidation via the `ETag`/`Last-Modified` nginx
  already sends — not `no-store`, which would force a full re-download every time for no benefit).
- **`ago-console`**: a Vite SPA build. `index.html` needs the identical "always revalidate" treatment
  as above (it is the one file whose staleness would mean loading an old shell entirely). Its built
  `/assets/*` files, if Vite's own default content-hashed filenames are confirmed still in use (verify,
  do not assume this has not changed since `15-07`), are the one case in this whole item where the
  *opposite* policy is correct — a hashed filename never means two different things, so those files can
  and should be cached aggressively and immutably (`Cache-Control: public, max-age=31536000, immutable`)
  once confirmed hashed, which is also the only real performance win this item can honestly claim.

## Scope

- Add an explicit `Cache-Control` directive covering every file class named above, in each of the
  three repositories' own static-serving config (`ago-console/nginx.conf`, and an equivalent
  `nginx.conf`/`add_header` block added to `ago-widget`'s and `ago-landing`'s Dockerfiles, which
  currently ship no custom nginx config at all).
- For `ago-console` specifically: confirm whether Vite's build still produces content-hashed filenames
  under `/assets/` before writing the immutable-cache rule — state what was found, do not assume the
  build config from `15-07`'s own day still holds.
- Verify live after deploying to demo: repeat the exact steps that surfaced this gap (`curl -i` for the
  header itself, and a real browser reload after a deploy) and confirm a normal reload — no hard-reload,
  no manual cache bypass — picks up a new deploy.

## Out of scope

- A CDN or edge-cache layer in front of these origins — this item is about what the origin itself
  claims, not about adding infrastructure that is not there today.
- Any change to the four images' own build process, filenames, or artifact identity — `15-07`'s own
  scope, already done; this item only adds a response header.

## Done when

- [x] `curl -i` against each of the four frontends' main entry file shows an explicit `Cache-Control`
      header, not nginx's own bare defaults.
- [x] A real deploy of a changed commit is picked up by a normal browser reload (not a hard-reload, not
      a manual cache bypass) — proven live against the demo, the same way this gap was originally found.
- [x] If `ago-console`'s built assets are confirmed content-hashed, they carry an immutable long-lived
      `Cache-Control`; if they are not (or that could not be confirmed), state so plainly and apply the
      same always-revalidate policy every other file in this item gets, rather than guessing.

## Outcome

Verified live 2026-08-31, from the VPS node itself (curl against a real browser's cache is not
trustworthy from this environment's own sandboxed network path — see this repository's own operational
notes on the outbound proxy):

```
console.reserve-me.ru/    -> cache-control: no-cache
demo-shop1.reserve-me.ru/ -> cache-control: no-cache
demo-shop2.reserve-me.ru/ -> cache-control: no-cache
reserve-me.ru/            -> cache-control: no-cache
console.reserve-me.ru/assets/index-2Ol8xuHJ.js -> cache-control: public, max-age=31536000, immutable
```

Confirms both open questions this item named: `ago-console`'s Vite build still content-hashes
`/assets/*` filenames, and every fixed-filename file across all four images now revalidates instead of
serving an unbounded, uncontrolled stale copy. `ago-landing`'s own image needed a second, unplanned fix
(`ago-landing#8`) before it could publish at all — its Trivy scan started failing on a real, unrelated
CVE (`CVE-2026-14456`) once this item's own image tried to go through `publish-images` for the first
time, closed by applying the `17-04` apk-upgrade pattern `ago-widget`/`ago-console` already carried.
`ago-deploy#102` pinned all three affected repositories' new commits in the demo overlay's
`kustomization.yaml` and `deploy.sh` moved the live cluster to them, `smoke.sh` green throughout.

## Open questions

None load-bearing — the two policies above (always-revalidate for fixed-filename files, immutable-cache
for confirmed-hashed ones) are standard, well-understood HTTP caching practice; the only genuine unknown
was a fact to go verify (whether `ago-console`'s `/assets/*` are actually hashed today), not a design
decision, and it is now confirmed above.
