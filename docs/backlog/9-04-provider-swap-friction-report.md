# Stage 9 capstone: the honest friction list

- **Stage**: 9
- **Status**: ready
- **Depends on**: `9-01-kafka-messaging-adapter.md`, `9-02-mysql-persistence-adapter.md`,
  `9-03-provider-config-switch-and-ci-matrix.md` - this item adds no new adapter code or CI wiring,
  only the synthesis, and it must be written from what those three items actually found, not in
  advance of finding it

## Goal

A short, honest document exists that lists every real friction found while building both alternate
adapters and proving the switch - the deliverable `roadmap.md` actually asks for is this document, not
a polished, leak-free abstraction. A reviewer reading it should come away trusting the project's
architecture claims *more*, not less, because the boundaries where the abstraction cost something are
named plainly instead of hidden.

## Context to read first

`docs/architecture/messaging.md`'s "Known leaks" section and `docs/architecture/data-model.md`'s
"Provider swap (Stage 9)" section - both were written *before* the adapters existed, as predictions;
this item checks each prediction against what `9-01`/`9-02` actually found and states whether it held,
partially held, or was wrong. `docs/adr/0006-broker-abstraction.md`'s "Consequences" section and
`docs/adr/0004-postgres-ef-writes-dapper-reads.md`'s "Consequences" section - the costs each ADR
already admitted to up front; this item is where those admissions get a real number or a real example
behind them instead of staying abstract. `docs/adr/0011-utc-datetimeoffset-everywhere.md`'s own line
("that friction goes on the Stage 9 list") and `docs/adr/0017-generic-outbox-inbox-writer.md`'s claim
("Stage 9's MySQL swap reuses the same generic writer/checker unchanged") - two specific claims made
by name, each needing a specific yes/no/partial answer here. The `load-test` skill's Reporting section
("a report that only contains wins is not a measurement, it is a brochure") - the same honesty
discipline `7-06`'s report already applied to load numbers, applied here to architectural claims
instead. `7-06-stage-7-load-proof-report.md` - read as the template for tone and structure at a
different subject.

## Scope

- One document, `docs/architecture/provider-swap-friction.md` (an architecture doc, not a `load/`
  report - this is a design-boundary finding, not a performance number, so it belongs where
  `messaging.md`/`data-model.md` already live and can be cross-linked from both).
- A section per known-leak category, each stating what was predicted (with a citation to the ADR or
  architecture doc that predicted it) and what was actually found:
  - **Ordering scope** - Kafka per-partition vs. RabbitMQ per-consistent-hash-queue; whether the two
    were actually equivalent for this project's partition-key usage, as `adr/0006` claimed, or whether
    building `9-01`'s ordering test surfaced a real difference.
  - **Replay semantics** - Kafka's offset replay vs. RabbitMQ's none; whether anything in `9-01`'s own
    build tempted a design that would have depended on replay, and how that temptation (if any) was
    resisted or avoided.
  - **`jsonb` vs `json`** - whatever `9-02` actually found about MySQL's `json` column type versus
    Postgres's `jsonb` for the `outbox`/`webhook_deliveries` payload columns (indexing, query
    capability, storage form) - concrete, not a restatement of the general SQL-standard difference.
  - **`SKIP LOCKED` behaviour** - whether MySQL 8's `FOR UPDATE SKIP LOCKED` actually matched Postgres's
    semantics under `9-02`'s own operator-capacity and waiting-queue concurrency tests, or whether a
    real difference in lock granularity/isolation-level interaction showed up under
    `Ago.Chat.Concurrency.Tests`.
  - **Offset/timestamp handling** - `adr/0011`'s own flagged friction: how `DateTimeOffset` actually
    round-tripped through MySQL's provider versus Npgsql's, and whether `1-04`'s own Dapper
    exact-type-binding lesson (`DateTime` read from the driver, converted explicitly) needed a MySQL
    equivalent or something different again.
  - **Optimistic concurrency without `xmin`** - not originally on `data-model.md`'s named list, but a
    real gap this item's own Context section identifies (`9-02`'s Context) - what replacement mechanism
    `9-02` actually used for `conversations`, and whether it is weaker, equivalent, or stronger than
    `xmin` in any observable way.
  - **Partitioning syntax and maintenance** - MySQL `RANGE COLUMNS` vs. Postgres declarative
    partitioning, and specifically whether `PartitionMaintenanceJob`'s provider-specific-DDL problem
    (named in `9-02`'s Context) was cleanly solved behind a port or needed a compromise worth naming.
  - **Case-sensitivity of identifiers** - whatever `9-02` actually found about MySQL's
    collation/case-sensitivity defaults for table and column names versus Postgres's, and whether it
    caused a real bug during development worth recording as a warning to a future reader.
  - **Anything not predicted at all** - the most valuable section: any friction `9-01`/`9-02` hit that
    no architecture doc or ADR anticipated. If this section is empty, say so plainly rather than
    omitting it - an empty "unpredicted frictions" section is itself a claim worth being honest about
    (either the predictions were unusually complete, or not enough was tested to surface more; state
    which seems true).
- A short closing section: given everything found, does `adr/0004`'s and `adr/0006`'s original
  reasoning still hold? If either ADR's Consequences section understated a real cost, this item
  proposes (but does not itself write) an ADR amendment, the same way `messaging.md`'s `5-11` section
  documents an amendment that was made elsewhere - naming the gap is this item's job, writing the
  amendment can be a fast follow-up.
- Cross-links added from `docs/architecture/messaging.md`'s "Known leaks" section and
  `docs/architecture/data-model.md`'s "Provider swap (Stage 9)" section to this new document, so a
  reader following either doc's forward-looking prediction lands on the real answer.
- `docs/roadmap.md`'s Stage 9 section: checked against what was actually built across `9-01`-`9-04`;
  corrected in this same change only if something genuinely drifted (a deliverable renamed, a scope
  line no longer matching reality) - `CLAUDE.md`'s "docs are part of the deliverable" rule, applied the
  same way `7-06` and `6-06` already apply it to their own stages.

## Out of scope

- Building or fixing anything the friction list reveals - matching `7-06`'s own Out-of-scope rule
  ("fixing anything the numbers reveal... same rule as `7-05`'s own"), applied to design findings
  instead of load numbers. A friction that turns out to need a real fix (an ADR amendment, a port
  change) is reported here and handed back as a new backlog item, not quietly patched in this branch.
- Any new adapter code, test, or CI wiring - this item synthesizes what `9-01`-`9-03` already built and
  ran; if a gap is found (a leak nothing tested), that gap is reported honestly, not quietly filled in
  by running something new outside the already-reviewed scope.
- A general essay on Clean Architecture's merits - the document stays grounded in what was actually
  found building these two specific adapters, not a broader argument the project's own README (`8-03`)
  already makes its case for.

## Done when

- [ ] `docs/architecture/provider-swap-friction.md` exists, covers every category named in Scope above,
      and every claim in it traces to something actually observed while building `9-01`/`9-02`/`9-03` -
      a finding, not a restated prediction.
- [ ] The "anything not predicted" section is present and either lists real findings or explicitly
      states none were found and why that might be.
- [ ] `messaging.md` and `data-model.md` cross-link to the new document from their own
      prediction/friction sections.
- [ ] `roadmap.md`'s Stage 9 section double-checked against what was actually built; corrected in this
      same change if it drifted, left untouched if it didn't.
- [ ] Any finding that implies an ADR's reasoning no longer fully holds is named explicitly, with either
      a proposed amendment or a linked follow-up backlog item - none are quietly absorbed into "still
      basically true."

## Open questions

None - this item's entire content is a report on work `9-01`-`9-03` will already have finished; there
is nothing here for the author to decide in advance.
