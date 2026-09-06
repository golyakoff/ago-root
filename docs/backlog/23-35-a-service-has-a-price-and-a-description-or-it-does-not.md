# a service has a price and a description — or it deliberately does not

- **Stage**: 23
- **Status**: ready. **Answered by the author, 2026-09-06: a service has a price and a description.**
  It is work now, not a question.
- **Depends on**: `23-31` moves the service dictionary onto its own screen
- **Decision**: **open.** The author raised it 2026-09-06; the commercial half is not decided

## Goal

Whatever a tenant's service list is for, it holds what that purpose needs — and if it holds a price,
everyone knows who that price is a promise to.

## What is actually true today, verified 2026-09-06

`Ago.Calendar.Domain.Service` has **two fields**: `Name` and `Duration`. No price. No description.

And the dictionary is not a screen — services live inside `/calendar/setup` alongside the embed
snippet, the allowed origins and the calendars, which is four unrelated things on one page. `23-31`
gives them their own place; this item asks what belongs in them.

## The question, and it is not "add two columns"

**A price that a visitor sees at booking time is a commercial promise**, and it drags a train behind
it that a nullable `decimal` does not:

- Currency, and whether a tenant may have more than one.
- «от 2000 ₽» versus «2000 ₽» — a haircut priced by hair length is the normal case, not the edge one.
- What happens when the master charges differently on the day. A shown price that is routinely wrong
  is worse for the tenant than no price, because the visitor remembers the number.
- Whether it appears in the booking confirmation, which makes it evidence.

**A price only the operator sees** has none of those consequences and answers a much smaller question:
what did we agree this costs. That is a genuinely different feature wearing the same word.

**A description has the same fork**, smaller: shown to the visitor it is marketing copy the tenant
must maintain; internal it is a note.

## The three readings, and none is picked here

| | What it is | What it costs |
|---|---|---|
| **Internal reference** | Price and note visible only in the console | Two columns and a screen. No visitor-facing consequence at all |
| **Shown at booking** | The visitor sees price and description before confirming | Currency, "from" pricing, what the confirmation says, and a promise somebody has to keep |
| **Neither** | The dictionary stays name and duration | Nothing. The tenant keeps prices where they keep them now, which for a small shop is usually a wall |

## Scope, once the reading is chosen

- Whatever the answer, the service dictionary gets its own screen (`23-31`) and its fields follow.
- If the price reaches the visitor, it reaches `personal-data.md`'s reasoning too — not as personal
  data, but because the booking confirmation is a document a person keeps.

## Out of scope

- Payment. A price is not a charge, and `13-xx` owns money.

## Done when

- [ ] The author has picked one of the three readings, and it is written down.
- [ ] Whatever was picked is built, or the item is closed as not-planned with the reasoning kept.

## Open questions

- **Who is the price a promise to?** That single question decides everything above, and it is
  commercial rather than technical.

## The answer (author, 2026-09-06)

**A service has a price and a description.** Both, on the service itself, in the dictionary `23-31`
moved onto its own screen.

What still has to be decided *while building it*, and belongs in the change rather than back here:
what a price means when a service's real cost depends on the master or the duration, and whether a
visitor sees it before booking. Neither changes the answer above; both change the screen.
