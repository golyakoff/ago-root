# Skills

Skills live in `.claude/skills/<name>/SKILL.md`. Each is a procedure a session follows for a
recurring kind of work, so that the same decisions get made the same way across sessions that share
no memory. They are loaded on demand — `CLAUDE.md` stays short on purpose, and the depth lives here
and in `docs/`.

| Skill | Use it when |
|---|---|
| `vertical-slice` | Implementing any feature or backlog item end to end. The default skill for build work. |
| `clean-architecture-guard` | Unsure where a file goes, whether a dependency is legal, or how to shape a port. |
| `concurrency-review` | Touching threads, channels, consumers, shared state, ordering, cancellation or shutdown. |
| `messaging-contract` | Adding or changing an integration event, publisher or consumer. |
| `db-migration` | Changing schema, indexes, partitioning, or writing SQL. |
| `testing-guide` | Deciding what level to test at, writing tests, or chasing a flaky one. |
| `local-cluster` | Running the stack, changing manifests, or debugging why it will not come up. |
| `load-test` | Before any performance claim; tuning batch sizes or worker counts; Stage 6. |
| `adr-writer` | A decision was made between real alternatives, or a rule was deliberately bent. |
| `embeddable-widget` | Any change to the script that runs on third-party sites. |
| `commit-prep` | A slice of work is finished and ready for commit and push. |
| `land-a-slice` | The managing session is turning finished work into merged commits: verify, base check, PR order, queue sweep. |
| `background-worker-brief` | About to delegate a backlog item to a background worker — including deciding whether it deserves one. |
| `rebase-cleanup` | A branch looks wrong after a GitHub rebase-merge, or before deleting any branch. |
| `context-resume` | The start of a session continuing after a `/compact` context refresh. |
| `workspace-cleanup` | `C:\git\ago` has grown large, or periodically — remove worktrees/branches whose work already merged. |
| `dependabot-sweep` | Working through a repository's open Dependabot PRs — package bumps and CI-less infra image bumps alike. |

## How they relate

`vertical-slice` is the spine: it calls into `clean-architecture-guard` for placement decisions,
`db-migration` for schema, `messaging-contract` for events, and `testing-guide` for coverage. The
others are situational.

Three of them describe one loop and are best read as a sequence rather than alternatives.
`background-worker-brief` decides whether to delegate an item at all and, if so, what the worker
must be told. `commit-prep` is where any finished work stops — a worker hands its block back there
and goes no further. `land-a-slice` is what the managing session does with that block: verify
independently, check the base, open the PRs in the right order, sweep the queue. The split matters
because `CLAUDE.md` rule 9 grants the managing session something it deliberately does not grant a
worker.

## Rules for skills themselves

- A skill describes **procedure and judgement**, not facts. Facts (schema, topics, targets, layer
  rules) live in `docs/` and are linked, never duplicated — two copies of a rule become two different
  rules within a month.
- If a skill and a doc disagree, the doc wins and the skill gets fixed.
- Add a skill when the same instructions have been repeated in three sessions. Not before: an
  unused skill is context cost with no return.
