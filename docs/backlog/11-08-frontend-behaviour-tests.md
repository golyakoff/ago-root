# The frontends have tests for everything except what they do

- **Stage**: 11 — the stage that owns the two frontends. A name, not a schedule
  (`roadmap.md`'s "What comes next").
- **Status**: done
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

- [x] Each of the four behaviours has a test that fails when the behaviour is broken — demonstrated by
      breaking it, not by assuming. — eighteen deliberate breaks, listed in Outcome, each reverted at once.
- [x] Both suites run in CI. — already true when this was picked up; `ago-console`'s `npm test` step
      landed 2026-08-25 and `ago-widget`'s workflow always had one. Verified rather than assumed.
- [x] Each repository's README says what is tested and what is deliberately not.
- [x] No snapshot test and no coverage threshold was added.

## Open questions

None. The four behaviours are chosen; how each is best expressed is the implementing session's call.

## Outcome

**Counts.** `ago-console` 91 tests / 10 files → **122 / 13**; `ago-widget` 40 / 7 → **68 / 10**.
`typecheck`, `lint`, `test` and `build` green in both, and the widget's bundle is unchanged at
**21.0 KB gzipped** against its 45 KB budget — nothing added here is reachable from `src/index.ts`.
**No new npm package**, in either repository: `5-16`'s precedent held, and React 19's own `act` plus
`createRoot` in the already-configured jsdom environment is the whole mechanism. What a testing
library would have replaced is `ago-console/src/testing/dom.tsx` — about forty lines, most of it
comment — plus the one genuinely obscure trick it needs, going through `HTMLTextAreaElement`'s
*prototype* value setter so React's own value tracker does not swallow a typed character.

**What was tested, per behaviour, and what broke to prove it.**

- **Permission gating** (`auth/permissionGating.test.tsx`, 12 tests, plus the attachment-delete pair
  in `pages/ConversationPage.test.tsx`). The shell's navigation, the two `site:configure` pages, the
  platform-owner link, and the attachment-delete action — including the two fail-closed cases that
  are easy to get backwards: the answer has not arrived yet, and the call failed. The real
  `PermissionsProvider` is mounted with the endpoint faked, not a fabricated context value, because
  the path from the server's response to the rendered navigation is the thing being protected. Four
  breaks: ungating the shell (3 fail), `hasPermission` defaulting to `true` instead of `false` (3
  fail, including the admin page then issuing a request it should not have), removing both pages'
  own gates (2 fail), ungating the delete button (1 fail).
- **Reconnect and resume as behaviour** (`ago-widget/src/connection.test.ts`, 11 tests, and
  `ago-widget/src/ui/widget.test.ts`, 7). The console's half was already `5-16`'s; the widget's had
  nothing above `backoff`/`dedup`/`sequence`. Resume from the sequence actually seen, the gap
  delivered exactly once when the resume delta overlaps a live push, a reload resuming from the
  persisted cursor, a cursor that never moves backwards, and the send/refusal split — plus what the
  visitor sees: the composer disabled and re-enabled, resumed messages rendered once, a send that
  did not go saying so. Four breaks: resuming from `undefined` instead of `lastKnownSequence` (2
  fail), removing dedup (3 fail, one of them at the panel level), removing the pre-send state check
  (2 fail), the panel treating `reconnecting` as connected (1 fail).
- **Widget isolation on a hostile page** (`ago-widget/src/isolation.test.ts`, 10 tests). A jsdom twin
  of `demo/index.html`: global `!important` CSS, a page that reassigns globals, ids and class names
  colliding with the widget's own, a `localStorage` that throws, and the snippet pasted twice. Five
  breaks: no shadow root and styles into the host `<head>` (4 fail), removing the already-embedded
  guard (2 fail), unprefixing storage keys (2 fail), adding a second global (1 fail), removing
  `guardSync` so a malformed embed throws into the page (1 fail).
- **`11-06`'s composer and thread semantics** (`workspace/Composer.test.tsx`, 9 tests;
  `pages/ConversationPage.test.tsx`, 10). Enter/Shift+Enter/IME/Escape/empty-draft, the three ways a
  file is attached, the retry rule, and `5-15`'s mark-read. Breaks: Enter ignoring `shiftKey` and
  `isComposing` (2 fail), Escape not clearing (1 fail), the unknown-outcome retry minting a fresh
  `clientMessageId` (1 fail), mark-read dropping the visibility check (1 fail), mark-read dropping
  the debounce (1 fail — see below).

**The one test that had to be strengthened, which is this item's own thesis in miniature.** The
mark-read debounce test originally pushed three messages inside one `act`, so React batched them into
a single render and the test passed against an *undebounced* implementation. It certified nothing. It
now pushes each message in its own render, and fails that break with "expected 2 calls, got 4". Every
break above was run precisely because a behaviour test that cannot fail is worse than no test.

**`testing.md` was wrong about one thing, and is corrected in the same change.** It claimed the
widget's isolation claims — including "the host's CSS cannot reach in" — are testable in a DOM without
a browser. Three of the four are. The CSS cascade is not: measured, jsdom matches selectors against
the flattened document and implements no shadow-boundary scoping in `getComputedStyle`, so a host
page's `button { ... !important }` *does* apply to a button inside an open shadow root there, and the
shadow root's own `<style>` does not apply at all. An assertion would be wrong in both directions —
failing against correct code, and proving nothing if it passed. The automated test asserts the DOM
boundary underneath the rule instead — the widget's markup unreachable from the host document's own
queries, its stylesheet inside the root — and says out loud that the browser's half stays with
`demo/index.html` and live verification. **This is not a reason to reach for Playwright**, which the
item names as the thing to argue for rather than assume: one property of one file is not a browser
runner's worth of CI maintenance, and the hostile demo page already covers it where it is real.

**A real defect surfaced, reported rather than fixed here** (this is a testing item; a product change
belongs in its own): **in `ago-widget`, one failed send permanently offsets the optimistic-bubble
queue.** `ChatWidget.dispatchSend` pushes onto `pendingSends` before invoking and never removes the
entry when the send fails, while `handleIncoming` reconciles by queue *position* rather than by
`clientMessageId` (`protocol/dedup.ts` already names that as a known gap). After the ordinary
drop → send → reconnect sequence, the next message's own echo removes the "Not sent — reconnecting"
bubble instead of its own: the visitor loses the only sign their message never went, **and sees the
new one rendered twice**. Measured in a scratch reproduction, not reasoned — the panel ends on
`["second", "second"]`. Recorded in `ago-widget/README.md` and beside the test that found it; it
needs a backlog item of its own.

**Two smaller findings.** `ago-console/README.md`'s testing section still said "No unit tests yet" and
its source-tree listing still called the conversation pages `5-07` placeholders — both corrected while
writing the required statement. And `index.ts` treats an existing `window.AgoChat` as "already
embedded", so a host page (or another vendor) that owns that name silently gets no widget: the right
direction, since overwriting a global a page relies on would break it, but it was an undocumented
consequence of the double-embed guard and now has a test naming it as the decision it is.

**Not done, deliberately.** No coverage measurement and no threshold. No snapshot. No browser runner.
Nothing tested about `11-05`'s component set beyond behaviour that happens to pass through it. Layout
is untested by construction — jsdom has no viewport, which is also why `scrollIntoView` is stubbed
rather than asserted on. And live verification stays a required level for UI items; none of this
replaces it.
