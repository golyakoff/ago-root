# AGO Inbox: Telegram and WhatsApp — legal review and reliability spike

- **Stage**: 14
- **Status**: Telegram half done 2026-08-28 (`adr/0070`: reachability spike found a ~53%
  direct-connection failure rate, fixed by routing through a relay — real adapter work now scoped as
  `14-07`). WhatsApp's legal review remains unstarted and this item stays open for that half alone
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md` (the port either channel would
  implement, once actually started)

## Goal

Before either Telegram or WhatsApp gets a real adapter (`14-02`/`14-03`'s own shape, applied to a third
and fourth channel), this item names — and, for the technical half, actually investigates — the two
real prerequisites the product spec identifies for these two channels specifically, unlike MAX and SMS:
WhatsApp needs a genuine legal review before any Meta-API integration is built, and Telegram/Meta API
call reliability from a Russian-hosted server under network-throttling conditions is an open technical
question needing a real spike before committing engineering time. This item is that review/spike, not
the adapters themselves.

## Context to read first

`docs/backlog/14-02-max-channel-adapter.md`'s own "Context to read first" and Scope — the adapter shape
this item's own eventual adapters (once unblocked) would follow, unchanged. `docs/adr/0026-k3s-vps-
public-hosting.md`'s "Real payment constraint behind the provider choice" section — the same category
of real, external, Russia-specific constraint (there: Western payment processors; here: network
reachability of Western-operated APIs) that this item's own reliability spike has to actually test
rather than assume away. `docs/architecture/repositories.md`'s "no personal or employer data" rule and
`CLAUDE.md`'s "everything is public" framing — a legal-review finding for WhatsApp's Meta API terms
must be written up the way every other doc in this repository already is: for a stranger reading it,
with no confidential business advice presented as if this were a real legal opinion (state plainly, in
whatever this item produces, that it is the author's own reading of publicly available terms, not legal
advice).

## Scope

- **WhatsApp legal review**: read Meta's own Business/Cloud API terms and WhatsApp's own commerce
  policy as they stand at the time this item is picked up (they change; do not rely on this item's own
  prose without re-checking), and write a short, honest assessment of what a portfolio/demo integration
  would need to stay compliant (business verification, message-template approval for anything outside a
  24-hour customer-service window, the display-name review process) — the deliverable is the honest
  assessment itself, not a claim that it has been "cleared."
- **Telegram (and, if attempted, WhatsApp's own Cloud API) reliability spike**: from the same class of
  Russian-hosted VPS `adr/0026` already deployed to (or an equivalent throwaway instance), make a real,
  measured series of API calls to Telegram's Bot API over some real observation window, and record
  actual reachability/latency/failure numbers — `CLAUDE.md`'s "measure or stay silent" rule applies
  directly: this item's whole reason to exist is that nobody has measured this yet, so the deliverable
  is a real number, not a restated assumption that it "should probably work" or "probably won't."
- A short written finding (a note in this file's own "Done when" evidence, or a small ADR if the finding
  is itself a real "why we did/didn't build this" decision worth a permanent record — decide which once
  the finding exists) stating plainly: build Telegram now, defer it, or drop it; same for WhatsApp.

## Out of scope

- Any adapter code for either channel — this item is the review/spike, not the adapter. Telegram's own
  adapter, unblocked by this item's finding, is `14-07`.
- WhatsApp's adapter remains genuinely blocked on this item's own still-open legal-review half.
- MAX and SMS — already unblocked, `14-02`/`14-03`, unaffected by this item's own findings either way.

## Done when

- [x] A real, dated measurement of Telegram Bot API reachability/latency from a Russian-hosted VPS
      exists, with the actual numbers and method recorded — matching `load/reports/`'s own "real
      numbers, misses included" discipline, applied here to a reachability question instead of a
      throughput one. Done 2026-08-28: 15 requests over a 6-minute window, 7/15 (47%) succeeded at
      ~132ms average, 8/15 (53%) hit a full 10s connection timeout with no TCP handshake ever
      completing; a 5/5-successful control against an unrelated HTTPS endpoint in the same window rules
      out general VPS network flakiness. Full method and numbers in `adr/0070`.
- [ ] A written WhatsApp legal-review finding exists, stated as the author's own reading of public
      terms, not as legal advice, with an explicit compliant-or-not-yet conclusion.
- [x] Telegram's go/defer/drop decision is recorded — `adr/0070`: **build**, routed through a relay.
      Re-measured through it the same day: 15/15 (100%) succeeded, ~210ms average. Real adapter work is
      `docs/backlog/14-07-telegram-channel-adapter.md`, not this item. WhatsApp's own decision still
      waits on its legal-review box above.

## Open questions

Both prerequisites named above are the open questions this item exists to close — status stays
`blocked` until at least one channel has a real answer, matching this repository's own backlog rule
that an item with an unanswered open question does not get started.
