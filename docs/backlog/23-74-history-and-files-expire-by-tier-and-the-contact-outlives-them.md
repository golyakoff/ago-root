# history and files expire by tier, and the contact outlives them

- **Stage**: 23
- **Status**: ready
- **Depends on**: `adr/0031` (the retention class), `adr/0074` (the archive and attachment expiry),
  `23-08` (a contact is the tenant's asset).
- **Decision**: the tier grid, 2026-09-07 (`ago-business` `0012`). The numbers are decided; this wires
  them.

## What the grid asks for

| | Free | Paid |
|---|---|---|
| Conversation history and files | **2 months** | forever, while paid |
| Customer base, without history | **always** | always, while paid |

## The mechanism already exists, and one of its properties is worth selling

`adr/0031` partitions `messages` by an **immutable retention class derived from the tenant's tier at
write time**, and its own reasoning names the consequence: *an upgrade changes where future messages
land and moves nothing, and a downgrade destroys nothing.*

So a tenant who pays for a year and then drops to free **keeps everything written while they paid.**
The two-month window applies to what is written afterwards. That is not a caveat to explain away — it
is a promise worth making out loud, and today nobody says it anywhere a customer can read.

## The half that is a real requirement rather than a number

**"The customer base, without conversation history" means two objects with two different lifetimes.**
A contact must survive the deletion of the transcript it came from.

`23-08` already made a contact the tenant's own asset with its own clock, so the separation exists.
What this item has to prove is that expiry **actually respects it** — that dropping two-month-old
history does not take the contacts with it, by cascade, by partition drop, or by an erasure path that
treats a conversation as the owner of everything in it.

That proof is the item. The numbers are the easy part.

## Where this is likely to go wrong

- **Attachments are not messages.** `adr/0074` gives them their own expiry and their own archive; two
  months has to mean two months for both, and the bytes in object storage are the half that costs money
  and the half most likely to be forgotten.
- **Free-tier expiry is the first destructive scheduled job over a customer's own data.** It should be
  observable — how much was dropped, when — before it is trusted.
- **The window is a tier property, not a constant.** Wire it as configuration read from the tier rather
  than a literal, because the next thing the grid does is change it.
- **`24-09`'s gap is inherited**: an erasure request that cannot reach an archived message. Do not solve
  it here; check that this does not widen it.

## Out of scope

- Deleting an account for inactivity — `23-73`, a different promise and a much larger question.
- Changing what a retention class is. `adr/0031` decided that and it holds.

## Done when

- [ ] Free-tier history and attachments older than two months are gone, and it is visible that they were.
- [ ] Paid-tier history is untouched while the tier is paid.
- [ ] Contacts survive the expiry of the conversations they came from, proven by a test rather than
      reasoned about.
- [ ] History written while paid survives a later downgrade, proven — `adr/0031` says it does, and
      nothing asserts it.
- [ ] The window comes from the tier rather than a literal.
