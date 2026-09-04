# the vulnerability check cannot say it did not look

- **Stage**: 17
- **Status**: in review (2026-09-04) — `ago-console#100`, `ago-widget#53`
- **Found**: 2026-09-04, when `ago-console#99` could not merge and the reason looked like a
  vulnerability.

## The finding

`npm audit --audit-level=high` exits `1` **both** when it finds a High or Critical advisory **and**
when it cannot reach the advisory endpoint at all. Under a step named *Vulnerability check*, the
second is indistinguishable from the first.

The npm registry answered `503 Service Unavailable` on three consecutive attempts, and the whole of
what CI said was:

```
Process completed with exit code 1
```

Locally, against the same lockfile, the same command reported `found 0 vulnerabilities`. Nothing was
wrong with the dependencies. Nothing had been checked.

## Why this is the same defect `queue-audit.sh` already names

That script states it in its own header: **`gh` returning nothing is "could not look", never
"nothing to see"** — because an unreachable GitHub would otherwise read as a clean queue. `17-04`
built the npm policy without that distinction, and the shape has been there ever since.

Today's direction was the lucky one. An outage that looks like a finding **blocks**, and somebody
investigates. The opposite — an outage that reads as clean — merges with dependencies unchecked and
says nothing.

## The decision, and what it deliberately is not

**An outage still fails the build.** Not-checked is not a pass; the point is only that the log says
which of the two happened.

Three attempts with backoff, because a bulk POST to the registry is the shape that fails
transiently. They are **not** a fix for a sustained outage and do not pretend to be. A real finding
is not retried — that would only delay the same answer.

## Scope: two repositories, one promise

`ago-console` and `ago-widget` carry this step. `ago-landing` and `ago-calendar-console` do not. It
is one promise in two places, so one item (rule 15's amendment), landing as two small PRs.

`ago-platform`, `ago-chat` and `ago-calendar` run the .NET equivalent, which parses its own output
rather than relying on an exit code. Whether it has the same blind spot is **not checked here** and
is worth its own look.

## Done when

- [x] The log distinguishes *found* from *could not look*, proven by stubbing `npm` and running the
      step for each of the three outcomes — not by reading it.
- [x] The step's script is tested as extracted from the parsed workflow, so what was proven is what
      the runner executes.
- [ ] Both repositories carry it.
- [ ] `docs/runbooks/vulnerability-response.md` says what to do when the endpoint is unreachable,
      which today it does not — it covers findings only.
