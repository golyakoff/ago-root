# 25-187 · `public-demo-2` is dead code with no reachable build path

- **Stage**: 25
- **Status**: done — `ago-widget#111` (`25bc399`). Independently re-verified before merging: full diff
  review (the removed `resolveDemoPageLocale` resolver, the fixed-`"ru"` replacement, the updated
  Dockerfile/CI/README comments), `typecheck`/`lint`/`test` re-run directly (479/479, 39 files), and
  `grep -rn public-demo-2` confirming no caller remains anywhere. Also fixed two stray "shared demo
  shops" (plural) references in `panel.ts`/`config.ts` the item's own named-file scope missed, plus a
  stale "four static bundles... three repositories" claim in `docs/architecture/repositories.md`
  found while reviewing this item.
- **Depends on**: `25-182` (the teardown that made this true - filed the moment its own scope stopped
  short of this)
- **Found**: 2026-09-20, the managing session, landing `25-182` (`demo-shop2.reserve-me.ru` teardown).

## What is actually true today

`25-182` removed `ago-demo-shop2` everywhere it was actually built or served: `ago-deploy`'s
manifests, `ago-widget`'s CI publish job, and `k8s/build-static-images.sh`'s own local-build loop.
**Nothing anywhere builds an image from `ago-widget`'s `public-demo-2/` page any more.** That page,
the `DEMO_PAGE_DIR` build-arg value that selects it, and the real per-page behavioral branches in
`ago-widget/src/ui/widget.ts`/`src/demo/boot.ts` that read "is this `demo-shop1` or `demo-shop2`"
(the two fixed demo sentences in `8-06`/`8-11`, `boot.ts`'s own `lang="ru"` vs `lang="en"` check, and
at least one guarded-per-element check `boot.ts` states is "routinely false on demo-shop2 and that is
not a failure") all remain in the repository with no way to ever run.

This was found and deliberately left alone while landing `25-182`, rather than deleted on the spot:
removing real behavioral branches in `widget.ts`/`boot.ts` correctly is a different, larger task than
the mechanical manifest/CI edits `25-182` scoped - `boot.ts`'s own per-page checks are load-bearing
for whichever demo page *does* still get built, so removing the `demo-shop2` branch has to be checked
against `demo-shop1`'s own behavior, not just deleted.

## Goal

Remove `public-demo-2/`, the `DEMO_PAGE_DIR=public-demo-2` value, and every `demo-shop2`-aware branch
in `ui/widget.ts`/`src/demo/boot.ts`/`src/i18n/en.ts` - confirming, for each one removed, that the
remaining `demo-shop1`-only behavior is still correct (a check written for "either page" that only
`demo-shop1` will ever satisfy the moment this lands should be simplified to state that directly,
not left as a still-general check with one arm now unreachable).

## Out of scope

- `ago-demo-shop1` itself - untouched, still the one real public demo page.
- Any further change to `ago-deploy`'s own manifests - `25-182` already completed that half.

## Done when

- [x] `public-demo-2/` is deleted from `ago-widget`.
- [x] `DEMO_PAGE_DIR`'s own `public-demo-2` value has no caller anywhere in the repository (the
      build-arg mechanism itself may stay - `demo-shop1` still uses it - only the dead value goes).
- [x] Every `demo-shop2`-aware branch in `ui/widget.ts`/`boot.ts`/`i18n/en.ts` is removed or
      simplified to state the now-single-page reality directly, checked against `demo-shop1`'s own
      real behavior afterward (a live check or the existing test suite, not asserted from the diff).
- [x] `npm run typecheck`/`lint`/`test` green for `ago-widget`, with the relevant `boot.ts` tests
      updated to match rather than left asserting a page that no longer exists. — 479/479, re-run
      independently.
