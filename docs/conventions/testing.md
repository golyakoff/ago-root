# Testing

## Levels, and what belongs where

| Level | Project | Uses | Runs |
|---|---|---|---|
| Domain unit | `Ago.Chat.Domain.Tests` | Nothing external | Every build, milliseconds |
| Application unit | `Ago.Chat.Application.Tests` | Fakes for ports, fake clock | Every build |
| Architecture | `Ago.Chat.Architecture.Tests` | Reflection over assemblies | Every build |
| Integration | `Ago.Chat.Integration.Tests` | Testcontainers: Postgres, RabbitMQ, Redis, MinIO | Every build (slower), and CI |
| Concurrency | `Ago.Chat.Concurrency.Tests` | Real infra + stress loops | CI, and on demand |
| Load | `load/` (k6) | Deployed cluster | Stage 7 and before any performance claim |

Rule of thumb: a test that needs a container to prove a business rule means the business rule leaked
out of the Domain.

## The frontends

Added 2026-08-25, after the author asked why the two TypeScript repositories had almost no tests. The
answer was in this file: it described only .NET, and had said nothing about `ago-widget` or
`ago-console` since it was written. Two of six repositories were not covered by the document that
governs testing, so what got tested there was whatever a backend instinct recognised as testable —
pure functions with no DOM and no network (`backoff`, `dedup`, `sequence`, a validator). Every
component, every page, the auth flow and the permission gating had none. That was not a decision, and
this section exists so the next one is.

| Level | Where | Uses | Runs |
|---|---|---|---|
| Pure unit | beside the module | Nothing — no DOM, no network | Every build, milliseconds |
| Component / behaviour | beside the component | A DOM (jsdom or equivalent), fakes for the API and the hub | Every build |
| Widget isolation | `ago-widget` | A DOM plus a deliberately hostile host page | Every build |
| Rendered UX gate | `ux-gate/` in each frontend repo | A real browser (Playwright), seeded data, a token injected rather than typed | Every build |
| Live verification | a real browser against a running stack | Nothing automated | Before calling a UI item done |
| Deployment smoke | `ago-deploy/k8s/smoke.sh` | A deployed environment | After every deploy |

What belongs at each level, stated so it is not re-argued per item:

- **Test behaviour, not rendering.** "Enter sends and Shift+Enter does not", "a conversation the
  operator lacks permission for is not offered", "a failed send can be retried". Never "the button has
  class `x`" and never a snapshot — those fail on every restyle and pass through every real defect,
  which is the worst combination available.
- **The permission gating is worth testing even though it is not the real gate.** `usePermissions`
  hides what a caller may not do, and its own comment correctly says the server is the actual
  enforcement (`17-01`). Showing an admin control to a non-admin is still a defect, and it is one only
  a frontend test can catch.
- **Reconnect and resume is the widget's most valuable behaviour**, and the pure `backoff` function
  being tested is not the same as testing it. The behaviour is: the connection drops, sends queue,
  the client resumes from the right `sequence` and does not duplicate (`3-03`).
- **The rendered UX gate is a fourth level, and it exists because three defects reached the live
  deployment while every level above was green** (`15-11`, added 2026-09-02): the widget could not
  send a message, an input rendered one character wide on mobile, and an error message was dark grey
  on dark blue. The first belongs to the golden path; the other two are **measurements** — a rendered
  width and a contrast ratio — and measurements deserve a gate rather than a careful look.

  What it asserts, at 375x812 and 1280x800, on every screen it covers: no horizontal overflow, no
  interactive target under WCAG 2.5.8's 24px, and WCAG AA contrast computed from **rendered** styles.
  It also emits the screenshots the delivery digest uses, which is a second purpose and not a
  by-product.

  **It cannot live in the existing component level, and the reason is worth knowing: `jsdom` has no
  layout engine.** Geometry reads as zero and computed colour is unusable, so an overflow or contrast
  assertion written beside a component would pass on anything — a green that has measured nothing.
  That is why this level owns a real browser and the level above it does not.

  Three rules it earned the hard way, each from a real failure:

  - **Scope the colour and size checks to what this repository renders.** `ago-widget`'s gate measures
    only inside the widget's own shadow roots: its demo page is a deliberately hostile neighbour, and
    the first run dutifully reported the host page's green-on-white as a defect. Overflow stays
    document-wide there, because not damaging the host page *is* the widget's promise.
  - **Pierce the Shadow DOM, and prove that you did.** `document.querySelectorAll` and a `TreeWalker`
    do not enter one, so a copied check finds nothing in `ago-widget` and passes. Its gate carries a
    proof that injects a defect *inside* the shadow root, plus an assertion that the scan count is
    non-zero.
  - **Measure the target a person can hit, not the element.** A control inside a `<label>` is measured
    by the label; measuring the `<input>` alone flagged bare 13x13 checkboxes that were never 13x13 to
    a user. Measured rather than exempted, so a tiny label is still caught.

  **No step in a gate run types a password into a form.** Auth is a token injected into storage. That
  keeps the run reproducible in CI, and it is also what lets an AI session produce these screenshots
  at all.

- **The widget's isolation claim gets a test on a hostile page.** It runs inside a stranger's
  document; that the Shadow DOM holds, that nothing leaks into the global scope, and that the host's
  CSS cannot reach in are the claims the `embeddable-widget` skill is built on.

  **Three of those four are testable in a DOM without a browser; the CSS cascade is not**, and this
  sentence originally claimed otherwise. Measured while building `11-08` (2026-08-25): jsdom matches
  selectors against the flattened document and implements no shadow-boundary scoping in
  `getComputedStyle`, so a host page's `button { background: red !important }` *does* apply to a
  button inside an open shadow root there, and the shadow root's own `<style>` does not apply at all.
  An assertion on computed style would therefore fail against correct code and prove nothing if it
  passed. What the automated test asserts instead is the DOM boundary underneath the cascade rule -
  the widget's markup is unreachable from the host document's own selector queries and its stylesheet
  is inside the shadow root, which in a real browser is exactly *why* the host's rules cannot reach
  it. The browser's own half of the claim stays with the hostile demo page and live verification.
  Naming the split is the point: an isolation test that quietly asserts less than it appears to is
  worse than one that says what it cannot see.
- **Live verification stays a real level, not a confession.** `5-07` and `11-06` were both verified by
  working the real screen against a running stack, and that caught things no unit test would have. It
  does not survive a refactor, which is what the levels above are for — the two are complements.

**Coverage percentage is not a target here either** (see below), and on a UI it is actively
misleading: rendering every component once in a test buys a high number and proves nothing.

**Deployment smoke is a level, not an afterthought.** On 2026-08-25 the API was redeployed against a
database three migrations behind. Every page returned 200 — nginx was serving files perfectly — while
every query loading a `Site` failed. No unit test at any level above could have caught it, in either
language: the defect lived in the gap between deployed code and deployed schema. `smoke.sh` exists for
that gap and each of its checks names the incident it came from.

## How tests are written

- Names state the rule: `AssignTo_WhenOperatorAtCapacity_ReturnsCapacityExceeded`.
- Arrange/Act/Assert, one behaviour per test, no logic in the test body (no loops deciding
  expectations, no `if`).
- **No mocking framework for ports we own.** Hand-written fakes are readable, reusable and do not
  encode call-order assumptions nobody meant to make. Mocks are acceptable for third-party interfaces.
- Never mock the database. Use Testcontainers - a mocked repository proves the test compiles, nothing more.
- Fixed, controllable time via a fake `IClock`. No `Thread.Sleep` in tests: wait on a signal, poll a
  condition with a timeout, or use a deterministic scheduler.
- Test data through builders with sensible defaults, so a test names only what it cares about.

## Integration tests

- One Postgres/RabbitMQ/Redis/MinIO container set per test class collection, migrations applied once.
- Each test isolates itself by tenant (`site_id`) or by truncation - never by ordering.
- Assert observable behaviour, not table internals, except where the schema *is* the guarantee
  (unique `(conversation_id, sequence)`, outbox rows in the same transaction).
- **Every fixture that starts Testcontainers acquires `DockerResourceLock` first and releases it only
  after every one of its containers is disposed** (`Ago.Chat.Integration.Tests/DockerResourceLock.cs`).
  Testcontainers already isolates each fixture correctly (dynamic ports, separate containers) - this
  lock exists purely to bound how many container fleets are alive on the local Docker daemon at once,
  since parallel work (multiple background workers, each in their own git worktree, running
  integration tests at the same time) is a real CPU/memory contention risk that isolation alone
  doesn't address. Deliberate trade-off: this makes container lifetimes fully sequential machine-wide,
  even within a single test run that would otherwise start several collections' containers at once -
  correct under the assumption that avoiding Docker contention matters more than single-run
  parallelism; revisit (a small bounded concurrency count instead of strict 1) if that assumption
  stops holding.

## Concurrency tests

These are the project's headline claims, so they are explicit:

- Ordering: K messages, M threads, one conversation, repeated N times - persisted sequence must be a
  gap-free ascending run.
- Capacity: many workers racing to assign, asserting no operator ever exceeds capacity.
- Idempotency: deliver the same event twice, assert one row and one delivery.
- Shutdown: kill a host mid-load, assert zero acknowledged-but-lost messages.
- Backpressure: saturate the channel, assert flat memory and no silent drops.

Flaky is not tolerated: a concurrency test that fails one run in fifty has found a real bug. Quarantine
the *bug*, not the test.

## Coverage

No target percentage. Coverage is a diagnostic, not a goal: the question asked in review is whether
every rule in the ADRs and the concurrency doc has a test that would fail if it were broken.
