# Seed: demo tenant and operator

- **Stage**: 1
- **Status**: ready
- **Depends on**: `1-04-postgres-persistence.md` (the schema this inserts into must exist)

## Goal

`ago-deploy/seed/` gains a script that inserts one demo `Site` and one demo `Operator`, so `1-06`'s
manual two-tab verification has something real to connect against without hand-writing SQL each time.
`ago-deploy/README.md` already names this as the reason `seed/` exists beyond the MinIO bucket.

## Context to read first

`docs/architecture/data-model.md`, `../ago-deploy/README.md`, `../ago-deploy/seed/` (the existing
MinIO bucket script — match its style and error handling).

## Scope

- A script (shell, matching `create-minio-bucket.sh`'s style) that runs the insert against whichever
  Postgres the caller points it at (compose or the cluster's Service) — idempotent: running it twice
  does not create a second demo site.
- The seeded operator is granted the one hardcoded `"Operator"` role (`adr/0016`) — whatever `1-04`'s
  schema needs to represent that (a role-assignment row, or a column, depending how `1-04` modeled
  it) gets set here, not left for `1-06` to patch in later.
- The demo site's `public_key` and the operator's identifier are printed on success, since `1-06`'s
  manual test and the operator-auth stub both need to reference them.
- No secrets: the demo operator's "password"/credential, whatever `1-06` lands on for the auth stub,
  is either derived deterministically and documented as a throwaway dev value, or generated and
  printed — never hardcoded into a committed file if it could be mistaken for a real credential
  (`repositories.md` — "no secrets, ever," including "not in a fixture").

## Out of scope

- Seeding actual conversations/messages — the manual test in `1-06` creates those live.
- Any seeding mechanism tied to the real operator-auth model (OIDC, Stage 5) — this seeds a row in
  `ago-chat`'s own database, nothing in an external IdP.

## Done when

- [ ] Running the script twice against a clean compose Postgres leaves exactly one demo site and one
      demo operator.
- [ ] `../ago-root/docs/runbooks/local-dev.md` and `k8s-local.md` each gain a line showing when to run
      it in the bring-up sequence.

## Open questions

None.
