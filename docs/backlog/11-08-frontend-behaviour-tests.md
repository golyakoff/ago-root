# The frontends have tests for everything except what they do

- **Stage**: 11 — the stage that owns the two frontends. A name, not a schedule
  (`roadmap.md`'s "What comes next").
- **Status**: ready
- **Depends on**: nothing. `conventions/testing.md`'s frontend section, added alongside this item, is
  what it is written against.

## Goal

The behaviour an operator and a visitor actually depend on is verified by something that runs on every
build, instead of by whoever last opened a browser. Not coverage — four specific behaviours, named
below, chosen because each is load-bearing and each is currently unprotected.

## What the audit found

Counted 2026-08-25, so a session picking this up starts from the real shape rather than "there are no
tests".

There *are* tests: four files in `ago-console` against thirty source files, six in `ago-widget`
against sixteen. And they cover the same thing in both repositories — `backoff`, `dedup`, `sequence`,
plus a handful of pure functions (`widgetConfigValidation`, `storage`, `attachments`, `appearance`).

That is: **exactly what can be tested without a DOM and without a network.** Every component, every
page, the auth flow, the permission gating and the realtime provider have none — fourteen `.tsx` files
in the console and the whole interface.

The pattern is not carelessness, it is a gap in the rules. `conventions/testing.md` was 64 lines that
mentioned neither frontend, so what got written was whatever a backend instinct recognised as
testable. Two of six repositories were not covered by the document governing testing, and nobody
decided that.

## Context to read first

`docs/conventions/testing.md`'s frontend section — the levels this item works at, and the two things
it forbids (snapshots, coverage targets) with the reasons. `ago-console/src/auth/PermissionsContext.tsx`
and its own comment on client-side hiding never being the real gate — correct, and not a reason to
leave it untested. `ago-console/src/realtime/protocol/` and `ago-widget/src/protocol/` — the pure
functions already tested, so this item does not redo them; what is missing is the behaviour they are
parts of. `docs/backlog/3-03-reconnect-resume-protocol.md` — the protocol whose end-to-end behaviour
is the subject. The `embeddable-widget` skill — the isolation claims the widget makes about itself.

## Scope

Four behaviours, each with a stated reason for being in a list this short:

- **Permission gating in the console.** An operator without a permission is not offered the control.
  The server is the real gate (`17-01`), and showing an admin action to a non-admin is still a defect
  — one only a frontend test can catch.
- **Reconnect and resume, as behaviour rather than as `backoff`.** The connection drops, sends queue,
  the client resumes from the correct `sequence`, and nothing is duplicated or lost. This is the
  widget's most valuable property and `3-03`'s whole subject, and testing the backoff function is not
  testing it.
- **Widget isolation on a hostile page.** The Shadow DOM holds, nothing leaks into the host's global
  scope, and the host's CSS cannot reach in. These are the claims the widget exists on, and they are
  testable in a DOM without a browser.
- **The composer and thread semantics from `11-06`.** Enter sends and Shift+Enter does not; a failed
  send can be retried; unread clears when a conversation is opened (which `5-15` is fixing
  server-side, and this is the client half that should not regress afterwards).

Plus, once those exist:

- **Wire both suites into CI** if they are not already run there, so the point is enforcement rather
  than availability.
- **State in each repository's README what is tested and what is deliberately not**, so the next
  person adding a screen knows which of the two lists it joins.

## Out of scope

- **Coverage as a number.** Explicitly: on a UI it is actively misleading, since rendering every
  component once buys a high figure and proves nothing. If a session finds itself adding a test to
  raise a number, it is doing the wrong thing.
- **Snapshot tests.** They fail on every restyle and pass through every real defect.
- **A browser-driving end-to-end suite** (Playwright or similar). A real option and a real
  maintenance cost; the four behaviours above do not need one, and adding a browser runner to CI is a
  decision with its own argument. If the reconnect behaviour turns out to be genuinely untestable in
  jsdom, that is the finding that would justify revisiting it — say so rather than quietly reaching
  for it.
- **Testing the design system's appearance.** `11-05`'s components are styling; there is nothing
  behavioural to assert about a `Badge`.
- **Replacing live verification.** It stays a level in `testing.md` and stays required for UI items;
  this item exists because it does not survive a refactor, not because it was wrong.

## Done when

- [ ] Each of the four behaviours has a test that fails when the behaviour is broken — demonstrated by
      breaking it, not by assuming.
- [ ] Both suites run in CI.
- [ ] Each repository's README says what is tested and what is deliberately not.
- [ ] No snapshot test and no coverage threshold was added.

## Open questions

None. The four behaviours are chosen; how each is best expressed is the implementing session's call.
