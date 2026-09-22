# 25-217 · `ago-calendar-console` no longer exists, and four documents still say it does

- **Stage**: 25
- **Status**: done — `ago-root#<this PR>`
- **Found**: 2026-09-22, `tools/queue-audit.sh` failed outright: `Could not resolve to a Repository
  with the name 'golyakoff/ago-calendar-console'`. Checked directly — `gh api
  repos/golyakoff/ago-calendar-console` returns a genuine `404 Not Found`, and `gh repo list golyakoff`
  lists `ago-calendar` but nothing named `ago-calendar-console`. This is not a permissions gap; the
  repository is gone.

## What is actually true today, confirmed against real history

`22-06` (2026-09-04) retired `ago-calendar-console` deliberately — the calendar's own screens folded
into `ago-console`, one app per tenant rather than one per product. That item's own §"On deleting
`ago-calendar-console`" states the decision explicitly: **"Emptied, not deleted, and deleting it is
argued against"** — its Deployment still served `calendar.` at the time, its image was a live GHCR
package, and archiving was chosen as reversible. `22-09` (retiring the DNS/cert/Keycloak-client side)
confirms the infrastructure teardown but never mentions deleting the GitHub repository itself.

**Reality has since diverged from that recorded decision** — the repository is not archived-and-visible,
it is fully absent. Confirmed with the author directly: deleted deliberately, later and outside any
backlog item this project's own queue records, once it was genuinely of no further use. Stated plainly
here anyway, because a reader of `22-06` alone would otherwise expect an archived repository to still
exist.

**Four places still assert the repository exists**, none of them updated when `22-06`/`22-09` landed:

- `tools/queue-audit.sh:59` — `MIRROR_REPOS` lists it, so every run of the audit fails outright on this
  one repository instead of completing, and everything the audit exists to catch went unchecked as a
  result. `23-30`'s own correction already documents the retirement in an item file, but nothing
  propagated that fact to this tool.
- `docs/architecture/repositories.md:33,206` — the repository table, and the "AGO Calendar's console
  qualified" note that names `ago-calendar-console` as the current shape.
- `docs/runbooks/workspace.md:8,11` — the workspace directory tree, and the paragraph explaining why
  the repository exists.
- `docs/architecture/secrets.md:193` — sweep 5's own repository list for `secrets.GITHUB_TOKEN`
  references, naming `ago-calendar-console` as one of five repositories checked.
- `docs/adr/0064-the-calendar-console-is-its-own-repository.md` — `Status: Accepted`, uncorrected.
  Per this project's own ADR convention, a superseded decision gets marked `Superseded by <new ADR>`
  with a pointer; `22-06` is a backlog item, not an ADR, so there is no ADR number to point at. Marking
  it `Superseded by 22-06` (a backlog item, named plainly as such rather than invented as a fake ADR
  number) is closer to true than leaving `Accepted` unqualified.

## Scope

- `tools/queue-audit.sh`: remove `ago-calendar-console` from `MIRROR_REPOS`.
- `docs/architecture/repositories.md`: remove the repository's own row from the table; correct the
  "AGO Calendar's console qualified" note to state what is true now (folded into `ago-console`,
  `22-06`) rather than describing a repository that no longer exists.
- `docs/runbooks/workspace.md`: remove it from the directory tree and its own explanatory paragraph.
- `docs/architecture/secrets.md`: remove it from sweep 5's repository list (re-running the sweep
  confirms the remaining four are still accurate).
- `docs/adr/0064-*.md`: change `Status: Accepted` to `Status: Superseded by 22-06` — the one line, per
  `adr-writer`'s own immutability rule; the body stays as the historical record of what was decided
  and why, unedited.

## Out of scope

- Any other stale cross-repository reference this sweep did not turn up — `git grep -l
  ago-calendar-console` across every repository's own docs is a larger sweep than one audit-tool
  failure justified starting today.

## Done when

- [x] `tools/queue-audit.sh` runs to completion without failing on this repository.
- [x] `repositories.md`, `workspace.md` and `secrets.md` no longer assert the repository exists.
- [x] `adr/0064`'s status line reflects the real, already-executed retirement.
