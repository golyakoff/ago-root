# Runbook: a personal-data incident

`16-05`. What to do when personal data held by this system is exposed, corrupted, or lost — and, just
as importantly, how to work out *whose* data and *how much*, which is a question this project can only
answer because `16-01` wrote the map first.

**This file is the engineering half and nothing else.** Whether a given incident must be reported, to
whom, on what deadline, and in what words is a **lawyer's determination**, tracked as an open question
in the private `ago-business` repository (`architecture/personal-data.md`, "What is not decided
here"). Every step below is written so that a lawyer asked that question has facts to answer it with.
Do not infer from the ordering below that any particular notification is or is not required.

## What counts as one

Four shapes, because the response differs:

1. **Disclosure** — data reached someone who should not have it. A leaked credential, a
   cross-tenant read, a log or backup artifact ending up somewhere public.
2. **Loss** — data that should exist no longer does, and no backup covers it.
3. **Alteration** — data was changed by someone who should not have changed it.
4. **Availability** — the data is intact but nobody can reach it. Included because the other three
   are often discovered while investigating this one.

A near miss — a hole found before anything went through it — is **not** an incident, and should be
handled as an ordinary security fix. `17-02` is the worked example: a live bearer token was being
written to the edge access log, and the honest description was "a defect found by an audit", not "a
breach". Recording the distinction matters, because treating every finding as an incident is how a
real one gets lost in the noise.

## Step 0 — the dependency this runbook has on `15-03`

**A deadline that starts at "when somebody happened to notice" is not a deadline anybody can meet.**
Everything below assumes detection is mechanical and prompt, which is `15-03`'s alerting
(`runbooks/alerting.md`). Two things about it are true today and must be read before relying on this
file:

- The five rules that exist watch **availability and capacity**, not confidentiality. Nothing alerts
  on a cross-tenant read, an unexpected export, or an anomalous volume of requests to one tenant's
  data. So the realistic detection path for a *disclosure* incident today is a person — a report from
  a tenant, a visitor, or a researcher — and not an alert.
- **The alerting path runs on the machine it is watching.** A quiet inbox is not evidence of health
  until `15-03`'s external check exists (`runbooks/alerting.md`, "What this does not cover").

Both are gaps, not process failures, and both are named here so that the response time this procedure
can actually achieve is not overstated.

## Step 1 — stop it getting worse, before you understand it

In this order, and do not wait for a full diagnosis:

1. **Preserve evidence before changing anything.** Container logs are now pruned on a schedule
   (`adr/0057`: 14 days, `ago-deploy/k8s/base/log-retention.yaml`) and Jaeger's traces are bounded to
   10000 and are **in memory only** — a pod restart destroys them, and restarting a pod is often the
   first instinct. So: `kubectl logs` the relevant pods to a file on your own machine, and pull any
   trace you care about out of Jaeger, *first*.
2. **Close the hole.** Rotate what leaked (`17-03`), revoke what can be revoked, take the affected
   path out of service if it cannot be fixed quickly.
3. Only then restart, redeploy, or roll back (`runbooks/redeploy.md`).

Two revocation limits worth knowing before you need them, both already recorded elsewhere:

- **A visitor token cannot be revoked.** It is a stateless signed JWT and the server keeps no copy
  (`adr/0034`, `personal-data.md`); the only server-side lever is rotating the signing key, which
  invalidates *every* visitor session at once. `adr/0048` shortened the lifetime to seven days, which
  bounds the damage but does not end it.
- **An operator access token lives five minutes** (realm `accessTokenLifespan`, `adr/0034`), so for
  that half the natural expiry is usually faster than any manual step.

## Step 2 — determine the affected scope

This is the step that only works because the map exists. Work down
`architecture/personal-data.md`'s table, store by store, and write the answer down per store rather
than reasoning about "the data" in general. The stores that hold something about a natural person, and
the question to ask of each:

| Store | The question |
|---|---|
| `messages.body` (Postgres) | Which conversations, and therefore which visitors and which tenant? |
| `attachments` + the MinIO objects | Which object keys — and note the known gap: deleting a conversation leaves its MinIO objects behind |
| Keycloak's `keycloak` database | Which accounts; also `username_login_failure` (an attempted username and the IP it came from) and `offline_user_session` |
| RabbitMQ `deliver-to-connections.{node}` queues and their DLQs | These carry **full message bodies** and the leaked ones are never drained — check whether the incident touched the broker's PVC |
| Redis | Rate-limit buckets keyed by client IP; the PVC's RDB snapshot means the keyspace is on disk |
| `webhook_deliveries.response_snippet` | Up to 2000 characters of a tenant's own server's response body |
| Container logs (incl. the edge access log) | Client IPs, for the last 14 days (`adr/0057`) |
| Traces (Jaeger) | Ids, routes, SQL statement text — no bodies, no tokens (`16-05` verified this); in memory only |
| Metrics (Prometheus) | Nothing person-shaped (`16-05` verified this); listed so it can be ruled out quickly rather than argued about |
| Backups | **30 days** of daily artifacts on the author's own machine (`adr/0050`) — a disclosure that includes a backup artifact is a disclosure of everything in it, up to 30 days back |
| AGO Calendar's `customers` / `events` | A phone number, a name, notes, and a no-show history. A different database with **no shared key** to AGO Chat's — a person affected in both cannot be matched across them |

Two limits of this step, both real and both better known now than mid-incident:

- **There is no log aggregation** (`16-05` Out of scope). Reconstructing "who read what" means reading
  per-pod logs by hand, within their retention window.
- **`sites.allowed_origins` and the tenant boundary are the only structure available.** There is no
  per-record access log, so "which rows were read" is usually answerable only as "which rows *could*
  have been read by this path".

## Step 3 — who is told, and in what order

**Order, not deadlines.** The deadlines are the lawyer's.

1. **The author** (the only operator today) — immediately, and before anything below.
2. **The lawyer**, with Step 2's written scope. This is the input to "is this notifiable, to whom, and
   when", and it is the step that must not be skipped or pre-empted by a guess.
3. **The affected tenant(s).** AGO's working position is that it is a **processor** acting on the
   tenant's instruction for visitors' conversation data, and a **controller** for its own account
   holders (`personal-data.md`, "Who answers to whom" — to be confirmed by `16-04` and a lawyer). A
   processor's first duty runs to the controller, which is why the tenant comes before their visitors:
   telling a shop's customers something before the shop knows would be wrong regardless of what the
   law requires.
4. **The regulator**, if the lawyer says so, in the form the lawyer specifies.
5. **Affected individuals**, if the lawyer says so — and for conversation data, normally *through* the
   tenant rather than from AGO directly, for the same processor reason.

## Step 4 — write it down while it is fresh

One file per incident, in the **private** `ago-business` repository, never in these public ones. What
it has to contain for step 2 to be repeatable next time:

- When it started, when it was detected, **by what** (an alert, a person, an audit) — the gap between
  the first two is the number that says whether `15-03` is doing its job.
- The scope table from step 2, per store, including the stores ruled out and why.
- What was changed to close it, with commits.
- What would have caught it earlier, as a backlog item rather than a resolution.

## What this runbook deliberately does not decide

- Whether any incident is notifiable, to whom, or within what period — the lawyer's, via
  `ago-business`.
- The text of any notification.
- Whether AGO is controller or processor for a given dataset. The working position above is
  `16-04`'s to confirm, and an incident is the worst possible moment to settle it for the first time.
