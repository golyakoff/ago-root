# no action may leave a tenant with nobody who can sign in

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing, but see `23-71`: it removes the reason the action was dangerous, and this
  rule should be built in terms of it rather than ahead of it. `23-68` recovers from a lockout that
  happens anyway.
- **Found**: 2026-09-07, by the author, **during a live demonstration**, on the live deployment.

## What happened

The author opened Команда → Сотрудники, pressed «вернуть место» against their own row, and locked
themselves out of their tenant permanently.

Not figuratively. `13-03` made a seat the thing that gates signing in:
`GetByExternalSubjectIdAndSiteIdAsync` returns only a row that **holds a seat and is not removed**, so
`OperatorIdentityClaimsTransformation` adds no `OperatorId` claim for a seatless operator. That is the
mechanism by which an unpaid-for operator cannot sign in, and it is correct.

The account had **one** operator. They released their own seat. Afterwards:

- they could not sign in, because they held no seat;
- nobody else could restore it, because there was nobody else;
- and every path that could restore it requires a signed-in operator holding `site:manage_operators`.

The tenant was unrecoverable from inside the product. It was fixed by an `UPDATE` against the live
database.

## The two rules the author proposed, checked for consistency

*«Нельзя удалить последнего и нельзя удалить себя.»* They are **consistent**: they overlap only when
you are the last one, and there both say the same thing — refuse. There is no case where one permits
what the other forbids.

**But they are not enough, and this incident is the proof.** Nobody was deleted. A seat was released,
which is a different action, and neither rule mentions it. The same hole exists for removing your own
last role.

## What this rule costs, and the half that removes the cost

**Read narrowly, this rule traps the administrator.** Signing in requires a seat, so "you may not
release the last seat that can manage operators" means the account's administrator must occupy a paid
operator seat forever, purely to keep the key to their own account. The author caught this on reading
it, and they are right: it forbids a shop owner from delegating chats to staff and staying a manager.

**The trap is not this rule. It is that a seat is two things at once** — a licence to be routed
conversations, and the key to sign in. `decisions/0006` never conflated them: *"only the owner **and**
as many operators as are paid for can sign in."* The implementation did.

`23-71` separates them. Once an administrator can sign in without a seat, releasing your own seat stops
being dangerous, and this rule stops being a restriction anybody notices — it goes back to guarding the
case it was written for: **removing the last person who can administer at all.**

**Both are wanted, and in this order.** `23-71` is the one that restores the intent; this one is the
guard that still has to hold afterwards, because "remove the last administrator" remains reachable no
matter how sign-in works.

## The rule that actually covers it

**No action may leave a tenant with nobody able to sign in and manage operators.**

That is a property of the *result*, not of the action, so it covers every route to the same place —
releasing a seat, removing an operator, stripping a role, and whatever is added later. It is also the
only formulation that does not have to be re-derived each time a new way to lose access is invented.

Three things follow, and they are scope rather than commentary:

- **The check is server-side.** A disabled button is a courtesy; the refusal has to be in the handler,
  because the API is reachable without the console.
- **The refusal must say why.** *«Вы последний, кто может войти»* is actionable. A generic 403 is the
  same dead end wearing a different hat.
- **Self-action is not automatically forbidden.** An admin releasing their own seat when a colleague
  also holds one is fine and should stay fine. Only the last-one case is refused.

## Where this is likely to go wrong

- **Counting the wrong thing.** "Operators on this site" is not the answer; "rows that can actually
  sign in *and* hold `site:manage_operators`" is. An account left with one seated operator who cannot
  manage operators is locked in a subtler way.
- **The race.** Two admins releasing their seats at the same moment can each see the other and both
  succeed. The count must be taken inside the same transaction as the write — `CLAUDE.md` rule 8's own
  reasoning, applied to a capacity check that decides a write.

## Done when

- [~] Releasing the last seat that can manage operators is refused, server-side, with a message saying
      why. **No refusal exists, and none is added** — checked against `ToggleOperatorSeatHandler`
      rather than assumed: since `23-71`, `Operator.CanSignIn` is `HoldsSeat || holdsManageOperatorsPermission`,
      and the permission half is resolved from a role assignment this handler never touches. So for the
      one operator this rule is about (a non-removed `site:manage_operators` holder), `CanSignIn` cannot
      go from true to false by releasing a seat - a count-based guard here would read a fact this handler
      cannot move and could never refuse. `adr/0152` has the full trace and the alternatives considered;
      `OperatorSignInEligibilityTests.CanSignInAsync_TheSoleManager_SurvivesReleasingTheirOwnLastSeat`
      (`ago-chat`) proves it by reverting `23-71` locally and watching the test fail.
- [x] Removing the last such operator is refused the same way. **Already shipped, by `23-26`
      (`be4e65f`, 2026-09-05), before this item was filed.** Since `23-71`, "non-removed
      `site:manage_operators` holder" and "can sign in and manage operators" are the same set, so
      `23-26`'s transactional last-manager count already is this invariant.
      `OperatorSignInEligibilityTests.CanSignInAsync_TheSurvivingManagerAfterARefusedSelfRemoval_CanStillSignIn`
      (`ago-chat`) adds the one check nothing before this item made: that the holder the count leaves
      behind can actually sign in, not merely that the count is nonzero.
- [~] Removing the last role that grants it is refused the same way. **Nothing to guard: this action does
      not exist in the product.** Role assignment is written exactly twice (site registration, invite
      redemption) and never afterward; role permissions are seeded once and have no editor. `adr/0152`
      records that whoever builds operator-role editing must apply this same invariant to it then.
- [x] Two simultaneous attempts cannot both succeed, proven rather than reasoned. Proven on real
      Postgres for removal by `RemoveOperatorConcurrencyTests` (pre-existing, from `23-26`). Seat
      release carries no refusal to race, by the finding above, so there is nothing left to prove
      concurrent-safe for that route.
- [x] A tenant with two admins can still do all three to themselves. True by construction for both
      routes that exist (neither guard keys off self vs. other); the role-removal route is not
      applicable, per above.

**Verified, not merely argued** (`ago-chat`, worktree `ago-chat-23-67`): `dotnet format` clean,
`dotnet build -c Release` 0 warnings/0 errors, `dotnet test -c Release` green across all six
`Ago.Chat.*` test assemblies including `Ago.Chat.Concurrency.Tests` and `Ago.Chat.Integration.Tests`
against real Postgres. See `adr/0152` for the fails-before demonstration (reverting `23-71`, and
separately weakening `23-26`'s guard, each makes the relevant new test fail; restored, suite green
again).
