# 25-183 · The brandbook is one page and shows no real components

- **Stage**: 25
- **Status**: ready — code merged as `ago-brandbook#2` (`605c37d`), independently re-verified before
  merging (`components.css`'s copied rules spot-checked byte-for-byte against the real
  `ago-console/src/components/components.css`, the font-loading claims confirmed directly in both
  `ago-console/index.html` and `ago-landing/index.html`, license claims checked, local `docker build`
  + all 5 pages/assets served 200, and a live browser pass: buttons render all tones/sizes/hover/
  disabled states, both dialog variants render open and correctly positioned, typography page renders
  as intended). **Not yet deployed to the live site** — see Done when.
- **Depends on**: `25-180` (the live site this item expands - `brandbook.reserve-me.ru`, `ago-brandbook`)
- **Found**: 2026-09-20, the author, moments after `25-180` went live: wants more pages - controls,
  dialogs, and other real UI elements, plus a closer look at typography ("у нас кстати бесплатный
  шрифт?" - and a real discrepancy answers that question more precisely than a yes/no, see below).

## What is actually true today

`ago-brandbook` is one scrolling page: four sections (color, type, icons, logo), each showing values
copied out of `ago-console/src/design/tokens.css` and `ago-landing/styles.css`. It shows **tokens**,
never **components** - no button, no dialog, no form field, nothing a person could look at to see how
the identity actually renders in a real screen.

**A real discrepancy, found while scoping this item, not assumed:** `ago-console/index.html`'s own
font-loading link pulls `Unbounded`/`Manrope`/`JetBrains Mono` - the family names `tokens.css`'s own
header comment says were "traced from `ago-landing`". **`ago-landing/index.html`'s own current
font-loading link pulls a different three: `Onest`/`IBM Plex Sans`/`IBM Plex Mono`.** The landing page
has been redesigned since the console's type tokens were traced from it - the identical shape of drift
`25-180`'s own "two palettes, both real" color section already documents honestly for the color tokens,
just never checked for type. All six families are legitimately free (served through Google Fonts, which
only hosts open-licensed families - confirm and name the actual license per family, most likely SIL Open
Font License, rather than asserting "free" without saying which license and why that's checkable).

## Goal

Turn the single page into a small, real multi-page reference site:

1. **A typography page** - both type systems shown honestly, the same "two, both real, not reconciled"
   treatment the color section already gives the palette discrepancy above. Real specimens (actual
   rendered text at each weight/size this codebase actually uses), not just family names. State each
   family's real license by name.
2. **A components page (or pages)** - `ago-console/src/components/{Alert,Badge,Button,Dialog,Field,
   Input,Panel,Select,Spinner,Table,Textarea,Tooltip}.tsx` is the real, shipped set - show each one in
   its real states (a button in its default/hover/disabled states, a dialog actually open, an alert in
   each of its tones, etc.), styled with the real CSS from `ago-console/src/components/components.css`,
   not redrawn or approximated.
3. Keep the existing color/icon/logo content, moved into their own pages rather than one long scroll,
   with simple top-level navigation between all pages.

## Where this likely lives, to save the next session's own discovery pass

- This is still a static site, no build step - multiple real `.html` files (mirroring `ago-landing`'s
  own `index.html`/`pricing.html` two-page precedent) with a shared `styles.css`/nav, not a framework.
- Pulling `ago-console`'s real component CSS in without pulling in React itself: read `components.css`
  and hand-author the equivalent static markup/classes for each component's real visual states - this
  page demonstrates the identity, it does not need to run the actual React components to do that
  honestly, the same way the existing color/icon sections already show real values without importing
  `tokens.css` as a stylesheet.
- Update `Dockerfile`'s explicit `COPY` list and `nginx.conf` for the new pages/assets - the same
  "explicit list, never `COPY .`" discipline `25-180`'s own Dockerfile already established.

## Out of scope

- Any change to `ago-console`'s own components or `ago-landing`'s own fonts - this item documents both,
  it does not reconcile the discrepancy it found or move either source repository onto a shared system.
  That reconciliation, if ever wanted, is a real, separate, author-level decision - name it as a finding,
  do not silently pick one system and call it canonical.
- A component playground/sandbox (editable props, live state toggles) - static, real-states-shown
  reference pages, not an interactive tool.
- Adding new components that do not exist in `ago-console` yet.

## Done when

- [x] The type discrepancy (`ago-console` vs `ago-landing`'s own current font stacks) is shown
      explicitly, with real specimens and each family's real license named. — `typography.html`,
      font-loading claims confirmed against both real `index.html` files, licenses confirmed
      (SIL OFL 1.1 for five families, Apache 2.0 for JetBrains Mono).
- [x] Every component in `ago-console/src/components/` has a real-states showcase on the new
      components page(s), styled from the real `components.css`, not approximated. — `components.html`
      + new `components.css`, all 12 components, spot-checked byte-for-byte against the real file.
- [x] The site has real navigation between pages (color, type, icons, components, logo) - not one long
      scroll. — shared `<nav>` in the header, confirmed every link resolves.
- [x] `docker build` still succeeds with the new files (`Dockerfile`'s `COPY` list updated), and the
      built image serves every new page - checked by running it locally, not asserted from the file list.
      — local build + run, all 5 pages and new assets (`components.css`) return 200.
- [ ] Deployed and confirmed live the same way `25-180` was - `curl https://brandbook.reserve-me.ru/
      version.json` returns the new commit, every new page reachable over the real hostname.
