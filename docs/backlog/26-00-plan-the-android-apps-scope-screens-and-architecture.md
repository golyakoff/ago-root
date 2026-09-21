# 26-00 · Plan the Android app's scope, screens, and architecture

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21, the author, opening Stage 26 - AGO Chat's operator console, reachable from a
  real native Android app. `vision.md` used to list "mobile apps" as explicitly out of scope; that
  line is corrected in the same change that opens this stage.

## What this item is, and what it deliberately is not

This is the **planning phase only**, by the author's own explicit sequencing: a written plan, then a
screen/navigation-flow inventory, then visual mockups, then the author's own approval - and **only
after that approval does any real Android/Kotlin development begin**. Writing application code,
scaffolding a Gradle/Compose project, or committing anything to `ago-android` beyond its own already-
initialised empty `main` is out of scope for this item. A later item (`26-01` onward, numbered once
this plan says what they are) is where development starts.

## Scope

**1. What actually has to be ported.** Read `ago-console`'s real, current source - its routes,
screens, and the permission model behind them (`docs/architecture/authorization.md`,
`Ago.Chat.Domain`'s own `Permission`/role types) - rather than working from a description of what the
console does. Produce a screen-by-screen inventory of `office.reserve-me.ru`'s own functionality,
each one marked: ports to Android as-is, ports with a mobile-appropriate redesign (name what changes
and why), or excluded.

**2. The platform-owner boundary, and the escape hatch the author already named.** The author's own
instruction: exclude functionality reachable only by a platform owner, *unless* porting it as-is
turns out cheaper or safer than carving it out - in which case say so plainly and port it, gated the
identical way the console itself gates it (`usePermissions()`'s own equivalent, not a separate mobile-
only permission check invented for this). Whichever way each platform-owner screen goes, the plan
states the reason, not just the outcome.

**3. The architecture question a second future client forces now.** The author intends a native iOS
app after this one. Decide, and justify:
- Fully separate native codebases (Kotlin/Compose for Android, Swift/SwiftUI for iOS) sharing nothing
  but an API contract, versus some shared layer - and if shared, how much and in what form (a thin
  API-client/models layer only, versus shared business logic via Kotlin Multiplatform or similar).
- Whether a third repository, `ago-mobile-common`, earns its own existence for whatever is actually
  shared - the author left this explicitly to this item's own judgement, not a foregone conclusion.
- This is exactly the shape of decision `docs/adr/` exists for (a technology chosen over a real
  alternative, expensive to reverse once two client apps depend on it) - write the ADR as part of this
  item's own deliverable if the analysis lands on a real decision, using the reserved number **0178**
  (confirm nothing else has claimed it since this brief was written, and add the index row in
  `docs/adr/README.md` in the same change per this project's own convention). If the honest answer is
  "not enough is known yet to decide", say that plainly rather than forcing a premature ADR - `24-04`'s
  own "states three readings and picks none" is the precedent for a real, filed non-decision.

**4. Screens, flows, mockups.** A navigation/flow inventory (which screen leads to which, and by what
action) covering the ported scope from point 1. Visual mockups for the key screens - a real Artifact
(this project's own established practice for visual review before code: `25-197`'s own touch-routing-
sheet mockup, iterated live with the author before a line of the real feature was written), styled
for a native Android surface (Material Design conventions, not a web widget skin) rather than a
reskin of the console's own web layout. Iterate on the author's own feedback inside the Artifact
before calling this deliverable done - the same live back-and-forth this project already uses for
every other visual mockup, not a single unreviewed pass.

**5. Where the plan itself lives.** The written plan and screen/flow inventory belong in
`ago-android/docs/` (that repository's own architecture documentation, the same way `ago-chat`/
`ago-calendar` each keep theirs) - landed there through a real PR against `ago-android`'s own `main`,
not left only in this item's own report. `ago-root` gets this item's closure (the standard `Status`/
`Outcome` update) and, if one was written, the ADR - not a duplicate copy of the plan itself.

## Out of scope

- Any Android/Kotlin project scaffolding, build tooling, or application code.
- The iOS app itself - only the architectural question of how much it will eventually share with
  Android.
- Any change to `ago-chat`/`ago-console`/`ago-widget` - this stage is additive, per its own Goal.

## Done when

- [ ] The screen-by-screen port inventory exists, each item marked ports-as-is / ports-redesigned /
      excluded, with a stated reason for every platform-owner-only screen's own disposition.
- [ ] The native-vs-shared-code architecture decision (and the `ago-mobile-common` question) is
      answered, with an ADR if the analysis reaches a real decision (reserved number `0178`) or an
      explicit, filed non-decision if it does not.
- [ ] A navigation/flow inventory covering the ported scope exists.
- [ ] Visual mockups for the key screens exist as a reviewed Artifact, iterated on the author's own
      feedback, and the author has explicitly approved them before this item closes.
- [ ] The plan and inventory are landed in `ago-android/docs/` through a real PR against that
      repository's own `main`.
- [ ] No Android/Kotlin application code exists anywhere as a result of this item.
