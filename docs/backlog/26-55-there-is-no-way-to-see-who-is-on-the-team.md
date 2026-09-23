# 26-55 · There is no way to see who is on the team, or who holds a paid seat

- **Stage**: 26
- **Status**: ready
- **Depends on**: `26-54` (Команда's first real screen, and the segmented control this adds to)
- **Found**: 2026-09-23, reading `ago-console/src/pages/OperatorsTeamPage.tsx` and
  `ago-console/src/api/operatorTeamApi.ts` against `ago-android` `main` at `b099282`, with the
  approved mockup Artifact ("AGO Chat для Android", `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`)'s own
  graph (`TeamChat -- "сегмент · site:manage_operators" --> People`).

## Found

An administrator carrying this app has no way to answer "who is on this site, and which of them is
occupying a seat I am paying for". The console answers it on one screen; the app's Команда
destination is one sentence saying it does not exist.

The seat question is the one worth carrying in a pocket, and it is not a simple boolean: since
`25-170` a seat belongs to one `(operator, role)` pairing, not to an operator account, so the founder
who holds both seeded roles can hold one role's seat and have lost the other's. Any port that renders
"holds a seat: yes/no" per person is rendering something the product stopped meaning.

## What is actually true today, confirmed against real code

- `app/src/main/kotlin/ago/chat/android/shell/PlaceholderScreens.kt:57-62` — nothing exists.
- The gate is one permission, already named in this app:
  `ago-console/src/pages/OperatorsTeamPage.tsx:46` (`OPERATORS_TEAM_PERMISSION = "site:manage_operators"`),
  drawn into the nav at `consoleNav.ts:345-347`. Android's own
  `core/domain/.../permissions/Permission.kt:37` already declares `SITE_MANAGE_OPERATORS`, with a doc
  comment that says exactly what this item is: "named here now so the item that builds Команда's real
  content has no second place to look for the string."
- Two reads, both plain REST on the chat API this app already talks to — no new base URL, unlike
  `26-48`:
  - `GET /api/v1/sites/{siteId}/operators` → `OperatorTeamResponseDto`
    (`operatorTeamApi.ts:123-125`, shape at `:25-37`)
  - `GET /api/v1/sites/{siteId}/operators/seat-assignment-summary` → `SeatAssignmentSummaryDto`
    (`:127-129`, shape at `:46-59`)
- The shape that matters: `OperatorTeamMemberDto.roles` is a **list** of
  `OperatorRoleSeatDto { roleName, holdsSeat }` (`operatorTeamApi.ts:20-33`), whose own comment
  records the `25-170` change verbatim — the flat `holdsSeat`/`roleNames` pair is gone, and
  `Operator.HoldsSeat` does not exist server-side any more.
- The summary is likewise per role: `RoleSeatAssignmentSummaryDto { roleName, heldSeats, limit,
  overLimit }` (`:46-51`), and `overLimit` is `heldSeats > limit` — a **read-time** fact, deliberately
  distinct from the *invite-time* refusal predicate (`heldSeats >= limit`), which
  `OperatorsTeamPage` computes itself. The two thresholds answer different questions and this item
  must not conflate them.
- A member with no `displayName` renders as the first eight characters of the operator id
  (`OperatorsTeamPage.tsx:53-56`) — which is this app's `IdentifierText`
  (`ui/components/IdentifierText.kt:26-36`), unchanged.

## Scope

One promise: **an administrator can see the site's operators and which seats are held, from the
phone.**

1. Команда gains a segmented control — Общение (from `26-54`) and Люди — with **Люди drawn only for
   `site:manage_operators`**, matching `consoleNav.ts:345`. An operator without it sees Команда with
   no segmented control at all, the "a destination with nothing inside it is not drawn" rule this app
   already applies one level up.
2. A `:core:domain` `OperatorTeamApi` port and a `:core:network` Ktor adapter for the two reads, built
   the way `ConversationsApi`/`KtorConversationsApi` are.
3. A card per operator: name (or identifier), email, and **one seat line per role**, never one per
   person. A card with two roles shows two seat facts.
4. The seats summary above the list, one line per role: held against limit, with the over-limit state
   drawn as the server's own read-time `overLimit` rather than recomputed on the client.

## Out of scope

- **Every write.** Inviting is `26-56`; the seat toggle, the role change and the removal are each a
  confirmation-bearing write against somebody's access to their job, and each is its own promise. A
  read-only roster is complete: "who is here and what am I paying for" is the whole question an
  administrator carries around.
- **The invite list** (`listOperatorInvites`, `operatorTeamApi.ts:157`). It belongs with the invite
  flow, not with the roster.
- The team room — `26-54`.

## Done when

- [ ] An administrator sees the real roster and the per-role seat summary; an ordinary operator sees
      no Люди segment.
- [ ] An operator holding two roles shows two seat facts, not one.
- [ ] An operator with no display name renders through `IdentifierText`.
- [ ] `overLimit` is read from the response, and no client-side seat arithmetic exists anywhere in the
      change.
- [ ] A read failure renders as a refusal with a retry, never as a raw exception class name (`26-59`).
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
- [ ] Checked on a real device against a site with more than one operator.
