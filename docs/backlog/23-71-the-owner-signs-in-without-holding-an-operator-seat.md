# the owner signs in without holding an operator seat

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing. `23-67` becomes a much narrower guard once this lands.
- **Found**: 2026-09-07, by the author, reading `23-67` and noticing that its rule forces an
  administrator to remain an operator forever.

## This is drift, not a new feature

`decisions/0006` says it plainly: *"only **the owner and** as many operators as are paid for can sign
in, and the owner decides which."* The owner is **additional to** the paid seats, in the decision, in
those words.

The implementation collapsed that. Today the owner is an ordinary `operators` row, and `13-03` made a
seat the thing that gates signing in — `GetByExternalSubjectIdAndSiteIdAsync` returns only a row that
holds a seat, so a seatless owner adds no `OperatorId` claim and cannot sign in at all.

So the account's administrator is **compelled to occupy a paid operator seat in order to administer**,
which is not what was decided and not what anybody would sell.

## What it costs today, concretely

A shop owner who does not answer chats themselves — an ordinary case, arguably the common one — either
burns one of their two free seats on somebody who never takes a conversation, or stays in the routing
pool and receives conversations they will not answer.

And it produced a real incident: the author released their own seat on 2026-09-07 during a live
demonstration and locked themselves out permanently, because the seat was also their key. `23-67`
prevents that by refusing the action. **This item removes the reason the action was dangerous.**

## Scope

- **An administrator can sign in with no seat**, and reach the administrative screens: operators,
  billing, site configuration, the invitation flow.
- **They are not in the routing pool.** No conversation is assigned to somebody who holds no seat —
  that is what a seat means and it should keep meaning it.
- **Taking a seat back is an ordinary action**, so an owner can become an operator again when they want
  to, without an invitation and without anybody's help.
- **The seat count is unchanged.** An administrator without a seat consumes none, exactly as
  `decisions/0006` says.

## The question, and it is the author's

**Is it the owner, or anybody holding the Admin role?**

`decisions/0006` says *the owner* — one person, the account's own. That is the narrow reading and it is
what was decided.

The wider reading — anybody with `site:manage_operators` signs in seatless — is what the author
described wanting (*«назначить двух других и остаться управленцем»*), and it is more useful: a shop
with two managers and three operators is an ordinary shape. But it is **not** what `decisions/0006`
says, and it has a price attached: every additional administrator is a person who can sign in and
consumes nothing, which is a per-seat pricing model with a hole in it if nobody bounds it.

Three shapes, and the choice decides the pricing conversation rather than the code:

- **The owner only.** Faithful to the decision. A tenant wanting two managers pays for a seat for one.
- **Any administrator, unbounded.** What the author asked for. Simple, generous, and per-seat pricing
  now depends on nobody making everyone an administrator.
- **Any administrator, bounded** — administrators are free up to some number, or count against a
  separate allowance. Honest, and it is one more number somebody has to justify.

## Where this is likely to go wrong

- **Sign-in and routing are being separated for the first time.** Everything that today reads "has an
  `OperatorId` claim" as "is an operator who can take conversations" has to be re-read. Assignment,
  presence, capacity and the queue all assume the two are the same thing.
- **`23-67`'s rule must be re-expressed in terms of this.** Once an administrator can sign in without a
  seat, "nobody can sign in and manage operators" stops being reachable by releasing a seat — which is
  the whole point — but the rule still has to hold for removing the last administrator.
- **An account with zero seated operators is now a legitimate state.** A shop that has not hired anyone
  yet. Nothing may treat it as broken.

## Done when

- [x] An administrator with no seat can sign in and reach the administrative screens.
- [x] They receive no conversations, asserted by a test rather than by inspection.
      `SkipLockedAssignmentClaimer` now requires `HoldsSeat && RemovedAt == null` at both claim sites, asserted by test rather than read.
- [x] They can take a seat for themselves without an invitation.
- [x] The seat count does not include them.
- [~] The owner-versus-any-administrator question is answered, and the answer is recorded where
      **Recorded, not yet merged.** Administrators counted separately from seats is written up in `ago-business` `docs/decisions/0011` and priced in `0012` — both are open pull requests awaiting the author, so somebody pricing this will read it once those land, and not before.
      somebody pricing this will read it.
