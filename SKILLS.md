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
| `finish-an-item` | **The moment the last PR for an item merges.** Merging the code feels like finishing and is not: the documentation half, the issue closed *with a reason*, the remote branch, the worktrees, the audit. Six checks, one minute. Written after the same session dropped this three times in one day. |
| `commit-guard` | **Every commit and every PR, in every repository.** The whole path: verify, read the diff, stage precisely, write the message to a file, then commit and open the PR through scripts that refuse a `Co-Authored-By` trailer, a stale base, an unpushed branch and being on `main`. Absorbed `commit-prep` on 2026-09-08 — the two described one moment and contradicted each other on the only question that mattered. |
| `land-a-slice` | The managing session is turning finished work into merged commits: verify, base check, PR order, queue sweep. |
| `take-a-backup` | Taking an encrypted backup of the live databases on demand - before a migration, a new database, or whenever one is asked for. |
| `background-worker-brief` | About to delegate a backlog item to a background worker — including deciding whether it deserves one. |
| `rebase-cleanup` | A branch looks wrong after a GitHub rebase-merge, or before deleting any branch. |
| `context-resume` | The start of a session continuing after a `/compact` context refresh. |
| `workspace-cleanup` | `C:\git\ago` has grown large, or periodically — remove worktrees/branches whose work already merged. |
| `dependabot-sweep` | Working through a repository's open Dependabot PRs — package bumps and CI-less infra image bumps alike. |
| `user-story-writer` | Turning what the product does into what a person is trying to get out of it, for a design pass. Carries this product's per-role objectives and the honesty and anti-manipulation rules that bound them. |

## How they relate

`vertical-slice` is the spine: it calls into `clean-architecture-guard` for placement decisions,
`db-migration` for schema, `messaging-contract` for events, and `testing-guide` for coverage. The
others are situational.

Three of them describe one loop and are best read as a sequence rather than alternatives.
`background-worker-brief` decides whether to delegate an item at all and, if so, what the worker
must be told. `commit-guard` is where any finished work stops — a worker hands its block back there
and goes no further. `land-a-slice` is what the managing session does with that block: verify
independently, check the base, open the PRs in the right order, sweep the queue. The split matters
because `CLAUDE.md` rule 9 grants the managing session something it deliberately does not grant a
worker.

## When a script is better than a skill

A skill is prose, and prose gets paraphrased. Where the same three checks have to be true every time
and getting one wrong is expensive, the procedure belongs in a script that refuses, not in a paragraph
that reminds:

| Script | Replaces the paragraph about |
|---|---|
| `tools/new-worktree.sh <repo> <item> <type> <slug>` | Creating a task worktree — fetches origin, proves the base equals `origin/main`, refuses a directory or branch that is already taken, and prints the `cd`. |
| `.claude/skills/commit-guard/commit.sh <message-file>` | Committing — takes a **file**, never an inline `-m`, so shell quoting cannot mangle the message. |
| `.claude/skills/commit-guard/open-pr.sh <title> <body-file>` | Opening a PR — same reason, and backticks in a body have destroyed it three separate times when passed inline. |

`tools/queue-audit.sh` is the same idea applied to the queue, and since 2026-09-08 it also checks that
every skill carries frontmatter.

## Rules for skills themselves

- **Every `SKILL.md` opens with YAML frontmatter carrying `name:` and `description:`.** Without it the
  skill is never registered, so it can never be offered and never invoked — it is a file, not a skill.
  Three were found in that state on 2026-09-08, `commit-guard` among them: written specifically to
  stop the shell-quoting failures and the forbidden trailer, listed in this table as mandatory, and
  bypassed every single time for two weeks because nothing could see it. The index said it existed and
  the runtime disagreed, and nothing compared the two until `queue-audit.sh` was taught to.
- A skill describes **procedure and judgement**, not facts. Facts (schema, topics, targets, layer
  rules) live in `docs/` and are linked, never duplicated — two copies of a rule become two different
  rules within a month.
- If a skill and a doc disagree, the doc wins and the skill gets fixed.
- Add a skill when the same instructions have been repeated in three sessions. Not before: an
  unused skill is context cost with no return.
