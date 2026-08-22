# Assignment engine: Redis distributed-lock alternative

- **Stage**: 4
- **Status**: ready
- **Depends on**: `4-02-assignment-engine-skip-locked.md`

## Goal

The same "claim a waiting conversation, assign it to a free operator" outcome as `4-02`, reached
through a per-operator Redis lock instead of `SKIP LOCKED`, config-switchable behind one port, so the
two mechanisms can be directly compared - `concurrency.md`'s own framing: "kept as an alternative
implementation behind the same port, to demonstrate the trade-off (fencing tokens, clock skew, lock
expiry vs work duration)." The deliverable is the comparison and its write-up as much as the code -
this item exists to be argued about, not just merged.

## Context to read first

`concurrency.md`'s "Operator assignment" section (mechanism B), `4-02`'s file (the mechanism this
compares against and the port shape it establishes), `adr/0009` ("Redis is not truth" - this is the
constraint that shapes the whole design here, read it fully, not just the title), `CLAUDE.md` rule 8
("Never cache what a write decision depends on... any compare-and-set read come from the database
inside the transaction") - **this rule is not optional even under the Redis-lock strategy**: the lock
only ever decides who gets to *attempt* a claim; the actual capacity compare-and-set is still `4-01`'s
Postgres `UPDATE ... WHERE active_chats < capacity`, every time, under both mechanisms. A design that
lets "I hold the Redis lock" stand in for "I have capacity" violates this rule and is not what this
item is asking for.

Also read `src/Ago.Platform.Caching.Redis/RedisLock.cs` (the existing internal lock helper, `3-04`) -
**do not reuse it as-is**. Its acquire failure mode is deliberately fail-open ("Redis unreachable for
the acquire itself - proceed unlocked"), correct for cache-stampede protection (worst case: a
redundant cache load) but wrong here (worst case: two Worker replicas both think they hold the lock
and both attempt the same claim - `4-01`'s atomic `UPDATE` still prevents a double-assignment even
then, but the lock's entire purpose was to avoid the wasted contention, so failing open defeats it
silently). Decide and document the failure mode this item actually wants (most likely fail-closed:
Redis unreachable means this claim attempt is skipped this tick, not attempted unlocked) as part of
the work, not as an afterthought.

## Scope

- A port for "the exclusive-claim-attempt step," implemented twice: one wrapping `4-02`'s `SKIP
  LOCKED` transaction (the default), one using a new per-operator Redis lock (`SET NX` acquire,
  token-checked Lua-script release - the same primitive shape as the existing `RedisLock`, but a
  fresh implementation with this item's own failure-mode decision, living wherever `adr/0004`'s
  one-project-per-technology rule places it - most likely alongside or beside `Ago.Platform.Caching.
  Redis`, decide and state which and why).
- Config switch between the two (site-level or global - decide and state which; global is simpler
  and probably sufficient, since this item's point is comparison, not per-tenant policy).
- Fencing-token reasoning made concrete, not just cited: what actually stops a lock holder whose TTL
  expired mid-claim from completing a stale write after a new holder has already acquired the lock?
  (`4-01`'s atomic `UPDATE` is the actual answer here too - state explicitly that the lock is a
  contention-avoidance optimization, and the database write underneath is what makes the outcome
  correct regardless of what the lock does. This is the trade-off write-up's central point.)
- An ADR (`docs/adr/`) comparing the two mechanisms - latency, failure modes, operational complexity,
  what each protects against and what it does not. `CLAUDE.md`: "a decision worth arguing about
  becomes an ADR, added in the same change."

## Out of scope

- Making the Redis-lock path the default - `4-02`'s `SKIP LOCKED` is `concurrency.md`'s stated
  default ("no extra infrastructure, no lock-lease expiry problems"); this item adds the alternative
  for comparison, it does not flip the choice.
- A third mechanism, or tuning either one against real numbers - Stage 7.

## Done when

- [ ] The same `Ago.Chat.Concurrency.Tests` contention scenario `4-02` proved (N waiting
      conversations, M operators, multiple concurrent claimers, repeated runs) passes with the
      Redis-lock strategy selected instead - same guarantees, same "no operator ever exceeds
      capacity" bar, not a weaker one.
- [ ] A test that kills Redis mid-run (Testcontainers) and confirms the stated failure mode actually
      happens (fail-closed: no claims attempted while Redis is unreachable, not a silent fall-through
      to unlocked claiming) - the failure mode is a design claim, not just a comment, until a test
      forces it to happen for real.
- [ ] The ADR is written, compares both mechanisms on their actual trade-offs (not a restatement of
      `concurrency.md`'s existing one-line summary), and states which is the project's default and
      why.
- [ ] `docs/architecture/concurrency.md` gets a "Shipped in `4-03`" note.

## Open questions

- Site-level or global config switch for which mechanism is active - default to global unless the
  author wants per-tenant comparison data; either is a small change, but pick one before writing the
  option-binding code so it is not redone.
