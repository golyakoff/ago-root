# where the data physically sits is evidenced, not inferred from a tier name

- **Stage**: 24
- **Status**: ready — **blocked on `24-19`, not on implementation**. The confirmation this item was waiting for cannot be obtained: the author decided 2026-09-06 that Fornex does not issue the documents `152-ФЗ` compliance needs, so the deployment moves. This item closes against the *new* provider's confirmation.
- **Depends on**: `24-19` for the primary node's own answer — that is where the provider changes. The backup-location and relay-egress answers depend on nothing and are still owed here.
- **Decision**: none yet — `adr/0026` records the purchase, not a location fact

## Goal

The localisation answer — where the databases holding personal data physically run — rests on
something a reviewer could check, and the same is true of the backups.

## What is actually true today, verified 2026-09-05 (`24-06`)

`adr/0026`'s "Post-decision update" and `runbooks/public-deploy.md:55` both record the same sentence:
Fornex, "Cloud NVMe 6", **Russia location**, Ubuntu 24.04. That is a purchase-page label, copied into
a decision record. Fornex is a **Spain-registered** provider operating a Russia-region line, which the
same ADR states — so provider domicile and machine location are two facts here, and only the second
one is about where data sits.

**Nothing in any repository establishes the second one.** `personal-data.md` says its own art. 18 п. 5
citation is "here for orientation, not as a reading"; what it does not say is that the *fact* under
the citation was never established either. It has been treated as settled since `16-01` turned it from
"a happy accident" into a standing constraint.

### Checked 2026-09-05, and it moved the answer halfway

A RIPE registry lookup of the node's address returns:

| Field | Value |
|---|---|
| `country` | **RU** |
| `netname` | **RU-FORNEX** |
| holder | Fornex Hosting S.L. (the Spain-registered entity) |

**That is real third-party evidence and it is considerably better than a tariff label** — a registry
somebody else maintains, checkable by a reviewer without our cooperation, and it resolves the apparent
contradiction the ADR left open: a Spanish provider holding a block registered as Russian is ordinary,
because the entity and the allocation are different facts.

**It is still not the fact the statute asks about.** A RIPE `country` field records where a block is
registered as being used, not where a machine physically stands; the two normally agree and are not
the same claim. An inspection asks for a document, not a whois record.

So the honest position after this check: *likely true, now partly evidenced, still undocumented.*

**Second, in the same shape**: `adr/0050` puts every backup artifact on "the author's own machine" and
records nothing about where that machine is. Both databases and the MinIO objects are in every
artifact.

**Third, and narrower**: `adr/0070` routes Telegram's outbound calls through the author's own personal
VLESS endpoint precisely *because* it egresses from a different network. Where it egresses is not
stated.

## What changed on 2026-09-06, and it answers this item rather than advancing it

**The author decided Fornex is out.** Not because the machine is in the wrong place — the RIPE check
above still makes Russia likely — but because **Fornex does not issue the documents this rule is
checked with**. That is a different failure and a worse one: a location that is probably right and
cannot be evidenced is, at an inspection, indistinguishable from a location that is wrong.

So the first Scope entry below — *request a written confirmation from Fornex* — is struck. It was the
right next step when it was written and it has no answer. The deployment moves instead, to VK Cloud,
Yandex Cloud or Selectel, and **that move is `24-19`**.

**What survives from this item is the method, not the conclusion.** The RIPE lookup stays in the
record: it is how the question was investigated, it is checkable by a reviewer without our
cooperation, and the same lookup is the first thing to run against the new address. So is the
principle the item was filed on — *record how each answer was established, not only the conclusion* —
which is exactly what makes a provider's written confirmation worth more than a tariff label.

**The other two answers are unaffected and still owed here**: where the backup copies physically live
(`adr/0050` says "the author's own machine" and nothing more), and where the Telegram relay egresses
(`adr/0070`). Neither depends on which provider hosts the node.

## Why this is a gap rather than an oversight

Nobody was ever asked to verify a location. `adr/0026` was answering "which VPS can the author
actually pay for", and answered it well; residency became a constraint later, in a different item, and
inherited the earlier item's sentence as if it had been evidence. The failure mode is specific: this
is the one element in `processing-instruction-facts.md` that cannot be checked by reading a file, and
it is the one where a confident wrong answer costs the most.

## Scope

- ~~**Request a written confirmation of the datacentre location from Fornex**~~ — **struck
  2026-09-06**: there is no such confirmation to be had, which is what `24-19` exists to fix. The
  sentence is kept struck rather than deleted, because "we asked and they do not issue one" is the
  finding, and a deleted line reads as a step nobody thought of.
- **File the new provider's written confirmation** once `24-19` has moved the deployment, together
  with a RIPE lookup of the new address — the same evidence, from the same method, about a machine
  whose provider will also put it in writing.
- Record *how* each answer was established, not only the conclusion — the RIPE lookup is the first
  entry and it belongs in the record whatever the provider says.
- Record where the backup copies live.
- Record the relay's egress, or record that the Telegram channel's path is the reason it needs its own
  answer.
- Update `adr/0026`'s update section, `personal-data.md`'s residency section and
  `processing-instruction-facts.md`'s Element 5 to cite the evidence rather than the label. **The node
  address stays `<node-ip>`** in every public repository.

## Out of scope

- Whether the localisation rule applies to a given dataset, and what notification it implies. A
  lawyer's, per `personal-data.md`'s own boundary.
- Moving anything. If the answer is unwelcome, that is a separate decision with its own ADR.

## Done when

- [ ] A provider confirmation of the datacentre location is on file, and the primary node's
      location is recorded with the method that established it and the date. The RIPE lookup of
      2026-09-05 (`country: RU`, `netname: RU-FORNEX`) is recorded as the first such method.
- [ ] The backup copies' location is recorded.
- [x] `processing-instruction-facts.md` Element 5 no longer contains the words "rests on a
      purchase-page label".
      *Done 2026-09-05. The section had begun contradicting itself: the finding's opening still made
      that claim while the paragraph below it recorded the RIPE evidence. The opening now states the
      current position — partly evidenced, not documented by the provider — and the original finding is
      kept below it in the past tense, because how a claim came to rest on a tariff name is the useful
      part of the record.*

## Open questions

- **Only the author can answer any of this.** No repository holds it and `24-06` was scoped away from
  every live system deliberately.
- **The provider statement has to be requested** — nothing in the workspace holds one. That makes this
  a correspondence rather than an hour, which is why it is worth starting before the notification to
  the regulator needs the answer rather than after.
