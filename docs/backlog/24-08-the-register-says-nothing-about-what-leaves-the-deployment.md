# the personal-data register covers what leaves the deployment, not only what it stores

- **Stage**: 24
- **Status**: done (2026-09-06)
- **Depends on**: nothing. `24-06` tabled the destinations; this item turns that into register rows.
- **Decision**: `docs/adr/0070-*` (the Telegram relay), `docs/adr/0078-*` (the AI kinds)

## Goal

`personal-data.md` answers "where does it live" for a destination outside this deployment as well as
it already does for a table.

## What is actually true today, verified 2026-09-05 (`24-06`)

The register is a table of **stores**. Every row is somewhere AGO holds bytes. Six channel adapters and
one LLM vendor can receive message text or a direct identifier, and none of them has a row:

- **MAX (`14-02`), Telegram (`14-07`), VK (`14-08`), Email (`14-09`), WhatsApp (`14-10`), Avito
  (`14-11`)** — registered unconditionally in `ChatModule`, activated per site by that tenant's own
  `channel_credentials` row. Message text and attachments cross to the provider.
- **YandexGPT (`19-01` reply draft, `19-02` categorisation)** — the conversation's own history, as
  prompt context. Gated on **AGO's** credentials, not any tenant's; no key is set in `ago-deploy` today,
  so nothing reaches it as of this date.
- **SMS (`14-03`, `14-15`)** — nothing. The only registered `IPhoneVerificationSender` is
  `UnconfiguredPhoneVerificationSender`; no SMS infrastructure project exists.

`processing-instruction-facts.md`'s Element 5 has the full table with sources.

The residency section's own vendor table still lists "`20-05`/`14-03` SMS and channel vendors — which
gateway" as a question to answer *before choosing*. Six of those choices have shipped.

## Why this is a gap rather than an oversight

The register was written 2026-08-25/26 (`16-01`, `16-05`), before any channel adapter existed, and it
was built to answer the question that mattered then: erasure and export against stores AGO controls.
Every adapter since has been a correct, reviewed vertical slice that added a *destination* — a
category the register has no column shape for. "Keeping this true" names three places that force an
update when a **schema** changes; nothing forces one when an outbound call is added.

## Scope

- A row per destination in `personal-data.md`, in that table's own columns — including "How long" and
  "What removes it", which for a vendor means *their* retention and *their* deletion path, cited or
  explicitly marked as not established.
- The residency vendor table updated to record what was chosen, per channel, rather than asking a
  question that has been answered by shipping.
- **A fourth entry in "Keeping this true"**: adding an outbound call that carries personal data updates
  this file. The mechanism that already exists for migrations and message contracts, applied to the
  thing that actually drifted.
- The AGO-side switch on `19-01`/`19-02` stated plainly in the register: no per-tenant control exists.

## Out of scope

- **Building a per-tenant AI opt-in.** Real, and a different promise — it changes the product, not the
  register. If it is wanted it gets its own item.
- Negotiating or reading any vendor's terms as a legal matter.
- Removing or restricting any channel.

## Done when

- [x] Every destination in `processing-instruction-facts.md`'s Element 5 table has a register row, or
      the register says explicitly why it does not.
- [x] Where a vendor's retention is unknown, the row says "not established" rather than being omitted.
- [x] "Keeping this true" names outbound calls.

## Open questions

- **How much of a vendor's terms belongs in an engineering register at all?** The honest floor is a
  link and a date; anything more is a summary that will rot. Decide once, apply to all six.

## Outcome (2026-09-06)

**The destinations are in their own table, not mixed into the store table, and that is the item's own
argument made structural.** Every row in the register above is somewhere AGO holds bytes; these are
somewhere bytes arrive that AGO does not hold. The columns are identical, but *What removes it* means
a different thing in each: above it names a mechanism this system runs, below it names somebody else's
— and mostly we do not know it.

**"Not established" appears seven times, and it is the honest answer rather than a placeholder.** What
a provider retains is derivable only from that provider's own terms, which `24-06` had already recorded
as unanswerable from these repositories. A guess here would be worse than the gap, because this file's
whole value is that a reader can act on it. The row says instead where the answer has to come from: the
provider the tenant themselves chose to connect.

**Two rows carry a finding rather than a fact.**

- **Telegram's outbound hop is not ours.** `adr/0070` routes it through a VLESS relay that is the
  author's own personal endpoint, because 8 of 15 direct requests from the node failed with no TCP
  connection at all. That ADR names it an accepted gap *"worth revisiting before any real paying tenant
  depends on Telegram specifically"* — and with a launch weeks away, that condition is close.
- **The AI switch is AGO's, deployment-wide, with no per-tenant control.** Nothing reaches YandexGPT
  today; no key is set in any overlay. But the day one is, every tenant's closed conversations start
  going to an LLM vendor and no tenant has anything to point at and refuse. A processor adding a
  purpose and a sub-processor on its own initiative is what an instruction exists to constrain.
  Building the control is a different promise and stays out of scope; the register now says the gap
  exists rather than leaving a lawyer to find it.

**The forcing function went where the work actually passes, not where it would read best.** The item
asked for a fourth entry in "Keeping this true". I first wrote a pointer to a `channel-adapter` skill —
**which does not exist**; caught before it shipped, and it would have been a guard nobody passes
through. The entry is `vertical-slice` step 6 instead, because an adapter is built as an ordinary
slice, and that skill now says what to write and that *"not established" is an acceptable answer and a
guess is not*.

**One pre-existing error fixed on the way.** That section's own count said "four" over five entries:
`24-15` had added a bullet and updated the number without noticing the paragraph below the list
introduces a further entry as "a fourth", so two entries claimed the same ordinal. That was my own
error from the day before, and a list whose count is maintained by hand drifts exactly like the
inventory it guards.
