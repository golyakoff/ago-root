# 26-26 · Release tag/title become the version, and the notes gain a real changelog

- **Stage**: 26
- **Status**: ready — dispatched to a background worker
- **Found**: 2026-09-22. The author asked directly for a different release shape:
  - The git tag becomes the version itself: `vX.Y.Z` (currently `release-<shortsha>`).
  - The release title becomes `Release vX.Y.Z` (currently `Release build <shortsha>`).
  - The install-instructions boilerplate paragraph is dropped from the notes entirely.
  - The notes gain a real changelog, built from commit subjects, rendered as checked checkboxes
    (`- [x] <one or two sentences>`), one line per feature/fix.
  - The existing final line — `Version <semver>, built from commit <full sha> — versionName
    <semver>+<shortsha>, versionCode <run_number>.` — is correct as-is and stays exactly as it is.

## What is actually true today, confirmed against `.github/workflows/ci.yml`'s `publish-apk` job

- **`Create GitHub release` step**: `tag="release-${{ steps.version.outputs.short_sha }}"`,
  `--title "Release build ${{ steps.version.outputs.short_sha }}"`.
- **`Write release notes` step**: a `cat > release-notes.md <<EOF` heredoc, currently: the boilerplate
  paragraph the author quoted verbatim (drop it), a blank line, then the one correct final line
  (`26-24`'s own addition — keep it byte-for-byte).
- **`26-24`'s own reasoning for the commit-named tag/title** (its comment directly above `Create GitHub
  release`): *"Every push to `main` publishes one of these, so many of them share a single
  `agoReleaseVersion` and a version-named tag would collide on the second push."* **This item
  deliberately overrides that decision on the author's own explicit instruction** — update or remove
  that comment rather than leaving it standing next to code that now contradicts it.

## The real problem `26-24`'s comment named, and the decision this item makes about it

Because `agoReleaseVersion` is a hand-bumped literal (not incremented every push), **more than one push
to `main` can carry the same version** — meaning `gh release create` will be asked to create tag `v0.1.0`
a second time while it still exists from the first. `gh release create` fails outright on an existing
tag; it does not update in place on its own.

**Decided shape: update the existing release in place rather than fail.** Before creating, check whether
a release for the computed tag already exists (`gh release view "$tag" --repo ... `, checking its exit
code rather than parsing output) and, if so, delete it first (`gh release delete "$tag" --yes
--cleanup-tag --repo ...`) so the subsequent `gh release create` is always a clean create. This means:
pushing again under the same hand-set version replaces that version's release with the latest build —
the correct behaviour for a version the author has not yet decided to bump, verified against a real
push of the same version before this is called done, not merely reasoned about.

## The changelog

**Commit range**: the most recent existing tag matching `v*` that is **not equal to** the tag about to
be created (or updated), to `HEAD`. This is deliberate, not "since the last release ran": it makes a
version's own changelog cumulative across however many times that version gets rebuilt before the
author bumps it, rather than resetting to empty on every same-version rebuild. If no earlier `v*` tag
exists at all (the very first release under this scheme), fall back to every commit reachable from
`HEAD` (or state a sensible bound if that list would be unreasonably long — use judgement, say what you
chose and why).

**Rendering**: one checkbox line per commit in that range, `- [x] <subject>`, from `git log
<range> --format=%s` (subjects only — this project's own commit convention already writes a real
sentence as the subject line, e.g. `feat(26-24): hand-set semver and a product-named release APK`;
don't invent a two-line "summary + body" scheme unless a subject line alone genuinely reads as
incomplete, which it usually won't here). Merge commits (if any reach this history — check whether
they can, given this project's own rebase-and-merge convention) should not produce an empty or
malformed line — verify this against the real commit history rather than assuming linear history.

## A second, unrelated gap the author also asked to close in this same item

`publish-apk` currently declares `needs: build-test` only — `instrumented-tests` runs concurrently with
no edge to it at all (confirmed in the real workflow graph: `build-test` → `publish-apk`,
`instrumented-tests` off on its own with no downstream dependent). That means a release can publish
successfully even when the UI tests are red, as long as `build-test` alone stayed green. Change
`needs: build-test` to `needs: [build-test, instrumented-tests]` so a broken back-button contract (or
any other instrumented failure) blocks the release the same way a broken unit test or lint failure
already does via `build-test`. This will visibly slow down `publish-apk` (it now waits for whichever of
the two jobs finishes last, not just `build-test`) — that is the intended trade, not a regression to
work around.

## Scope

- `.github/workflows/ci.yml`'s `publish-apk` job: `tag="v${{ steps.version.outputs.release_version }}"`,
  `--title "Release v${{ steps.version.outputs.release_version }}"`.
- Same job's `needs:` becomes `[build-test, instrumented-tests]`.
- The existing-release check-and-delete step, before `Create GitHub release` (or folded into it —
  your call on step boundaries, but the reasoning for the delete-before-create shape belongs in a
  comment either way).
- `Write release notes`: drop the boilerplate paragraph entirely; generate the changelog as described
  above; keep the final `Version ...` line exactly as it is today, unchanged.
- Update or remove `26-24`'s own comment reasoning about why the tag/title name the commit — it no
  longer describes what the code does.
- `Summarise what was published`'s own step-summary text references the old title/tag scheme nowhere
  directly, but check it for consistency with the new shape while you're in this job.

## Out of scope

- `versionName`/`versionCode`/the APK's own filename (`26-24`'s territory) — untouched.
- Any change to how `agoReleaseVersion` itself is bumped (still by hand, in its own commit) — untouched.

## Done when

- [ ] `publish-apk` depends on both `build-test` and `instrumented-tests` — a red instrumented-test run
      blocks the release exactly as a red `build-test` already does.
- [ ] The release tag reads `v<semver>` and the title reads `Release v<semver>`.
- [ ] Pushing a second time under an unchanged `agoReleaseVersion` updates that version's existing
      release (new asset, new notes) rather than failing — proven by actually exercising this path
      (a real second run against the same tag, not just reasoning about `gh release create`'s
      documented behaviour).
- [ ] The boilerplate install-instructions paragraph is gone from the notes.
- [ ] The notes contain a real changelog — one checked checkbox per commit subject since the previous
      distinct version tag — and still end with the unchanged `Version ...` line.
- [ ] `26-24`'s stale comment about the tag/title deliberately naming the commit is corrected or
      removed.
