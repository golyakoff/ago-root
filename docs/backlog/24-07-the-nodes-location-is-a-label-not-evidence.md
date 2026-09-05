# where the data physically sits is evidenced, not inferred from a tier name

- **Stage**: 24
- **Status**: ready
- **Depends on**: nothing. `24-06` found it; it is answerable independently of every other item here.
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

**Nothing in any repository establishes the second one.** No traceroute, no geolocation check, no
provider statement, no contract or invoice reference. `personal-data.md` says its own art. 18 п. 5
citation is "here for orientation, not as a reading"; what it does not say is that the *fact* under
the citation was never established either. It has been treated as settled since `16-01` turned it from
"a happy accident" into a standing constraint.

**Second, in the same shape**: `adr/0050` puts every backup artifact on "the author's own machine" and
records nothing about where that machine is. Both databases and the MinIO objects are in every
artifact.

**Third, and narrower**: `adr/0070` routes Telegram's outbound calls through the author's own personal
VLESS endpoint precisely *because* it egresses from a different network. Where it egresses is not
stated.

## Why this is a gap rather than an oversight

Nobody was ever asked to verify a location. `adr/0026` was answering "which VPS can the author
actually pay for", and answered it well; residency became a constraint later, in a different item, and
inherited the earlier item's sentence as if it had been evidence. The failure mode is specific: this
is the one element in `processing-instruction-facts.md` that cannot be checked by reading a file, and
it is the one where a confident wrong answer costs the most.

## Scope

- Establish, from outside this workspace, where the node actually is — and record *how* it was
  established, not only the conclusion.
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

- [ ] The location of the primary node is recorded with the method that established it and the date.
- [ ] The backup copies' location is recorded.
- [ ] `processing-instruction-facts.md` Element 5 no longer contains the words "rests on a
      purchase-page label".

## Open questions

- **Only the author can answer any of this.** No repository holds it and `24-06` was scoped away from
  every live system deliberately.
- Does a provider statement exist, or would one have to be requested? The difference decides whether
  this is an hour or a correspondence.
