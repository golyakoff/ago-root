# Known limits, and what a production team would do differently

This is the project's own list of where it is weak, what it built by hand that a team with a deadline
would buy, and which of its claims are smaller than they sound. It lives here rather than in
`README.md` because a facade should point at decisions and evidence, not open with a list of
regrets — but nothing here is softened, and none of it is hidden: the README links straight to this
file.

Two of the entries below are **decisions with ADRs behind them**, not oversights, and they are marked
as such. The rest are real debt.

## The list

- **The outbox and retry/dead-lettering are hand-built where MassTransit exists** — a decision, not an
  oversight, and [`adr/0006`](adr/0006-broker-abstraction.md) names MassTransit as "the correct choice
  for production work with a deadline" while rejecting it here, because it would supply the
  interesting part as a black box and demonstrating that competence is the point. **This entry is the
  one to read sceptically**, because it is the only place in this list where the portfolio goal and
  the commercial goal point in different directions. The ADR now carries the trigger that resolves it:
  the day a second engineer joins, or the day sagas or scheduling are needed, hand-built
  infrastructure stops being evidence and becomes maintenance nobody is paid for.

- **Cross-node connection fan-out is hand-built where a SignalR Redis backplane exists** — and this
  one is *not* the same kind of entry, despite looking like it. It was a decision with its own ADR
  ([`adr/0007`](adr/0007-connection-registry-instead-of-backplane.md)) and the backplane is the wrong
  tool here rather than the lazier one: it broadcasts every message to every node, so cost scales with
  cluster size instead of with recipients, and it is fire-and-forget pub/sub with neither ordering nor
  delivery guarantees — the two properties this product *is* (`CLAUDE.md` rules 4 and 6). It would
  also make presence unqueryable. The real cost of the choice taken instead is stated in that ADR and
  belongs here: more moving parts, and one extra broker hop in the latency budget.
- **The platform/product repository split has a real coordination cost**: a change that genuinely
  spans both repositories is four separate branches and merge requests — platform, product, deploy
  manifests, docs — each rebased onto its own `main`
  ([`architecture/repositories.md`](docs/architecture/repositories.md)). It's the right shape for
  proving the platform boundary is real (the platform genuinely cannot import product code), but it
  is real friction, paid on every cross-cutting change, and a single-repo monorepo with enforced
  package boundaries would very likely be the more pragmatic choice for an actual team.
- **The local cluster is one node** — no pod anti-affinity, no real node-drain or network-partition
  testing has ever run against it
  ([`runbooks/k8s-local.md`](docs/runbooks/k8s-local.md#known-limits-of-this-setup)). The public VPS
  deployment above is the same shape, for the same reason (cost) — it is explicitly a demo, not
  something carrying an uptime claim.
- **Stage 7's load numbers are honest, but small.** Every scenario ran at 1-3% of the target scale on
  a development workstation, not the provisioned cluster — see the Numbers section above and the full
  report it's copied from. A full-scale run is real, unfinished work, not a footnote.
- **A real bug reached this README's own live demo before being caught**: the widget's visitor-side
  send silently failed against every real deployment until this session's own verification pass found
  it (missing a required hub-invocation argument — [`5-12`](docs/backlog/5-12-fix-widget-visitor-send-missing-client-message-id.md)).
  It's a reminder that "the tests pass" and "a stranger can actually use it" are different bars, and
  only the second one is the one that matters to a user.

