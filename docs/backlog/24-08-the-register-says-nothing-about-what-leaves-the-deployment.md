# the personal-data register covers what leaves the deployment, not only what it stores

- **Stage**: 24
- **Status**: ready
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

- [ ] Every destination in `processing-instruction-facts.md`'s Element 5 table has a register row, or
      the register says explicitly why it does not.
- [ ] Where a vendor's retention is unknown, the row says "not established" rather than being omitted.
- [ ] "Keeping this true" names outbound calls.

## Open questions

- **How much of a vendor's terms belongs in an engineering register at all?** The honest floor is a
  link and a date; anything more is a summary that will rot. Decide once, apply to all six.
