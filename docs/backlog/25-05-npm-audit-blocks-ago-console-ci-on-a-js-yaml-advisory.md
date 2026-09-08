# 25-05 · npm audit blocks ago-console CI on a js-yaml advisory

- **Status**: done
- **Date found**: 2026-09-09
- **Depends on**: none

## What happened

`ago-console`'s CI runs `npm audit --audit-level=high` as a required check
(`docs/runbooks/vulnerability-response.md`'s table: "Critical/High in CI is already blocking"). Between
two runs of the same, unchanged `package-lock.json` a few hours apart — one green at 2026-09-08 20:15
UTC, one red shortly after — a new High-severity advisory was published against `js-yaml@4.0.0-4.3.1`
(`GHSA-2883-xcg3-v3hh`, a CPU-use denial-of-service in `maxTotalMergeKeys` for empty merge sources).
`js-yaml` is a transitive dependency of `eslint@9.39.5` via `@eslint/eslintrc` — a dev-only tool
dependency, never in the shipped bundle.

This is the mechanism working as designed (the runbook's own "nothing merges past it" row) — the
finding itself needed no product judgment, only a version bump — so it is filed and closed in the same
change rather than left for a person to triage, per this item's own resolution.

## What was done

`npm audit fix` resolved it with a single patch-level bump, `js-yaml` 4.3.1 → 4.3.2, entirely within
`eslint`'s own existing semver range — `package-lock.json` only, `package.json` untouched, `eslint`'s
resolved version unchanged. Re-verified: `npm audit --audit-level=high` reports zero vulnerabilities;
`typecheck`, `lint`, `vitest run` (103 files / 1046 tests) and `build` all still pass.

## Done when

- [x] `npm audit --audit-level=high` reports zero vulnerabilities in `ago-console`.
- [x] `typecheck`/`lint`/`test`/`build` all still pass after the bump.
