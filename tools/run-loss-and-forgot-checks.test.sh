#!/usr/bin/env bash
# Unit tests for the classify_* functions in run-loss-and-forgot-checks.sh - the part of 25-03 that
# decides CLEAN / FINDING / CANNOT-LOOK from a wrapped script's captured output. These are pure text
# functions on purpose (see that file's header), specifically so they can be tested here against
# canned fixtures without running git, gh, ssh, or the real checks - the same reason
# ago-deploy/k8s/overlays/demo/prometheus-alert-rules.test.yml exists for the alerting rules this
# item's mail delivery reuses: assert each boundary twice, silent one step below it and firing one
# step above.
#
# Run: bash tools/run-loss-and-forgot-checks.test.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/run-loss-and-forgot-checks.sh"

FIXTURES="$(mktemp -d)"
trap 'rm -rf "$FIXTURES"' EXIT

PASS=0
FAIL=0

assert_eq() {  # $1 label $2 expected $3 actual
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  $1 - expected [$2], got [$3]"
  fi
}

fixture() {  # $1 filename -> path; content read from stdin
  local path="$FIXTURES/$1"
  cat >"$path"
  printf '%s' "$path"
}

# ---------------------------------------------------------------------------- classify_queue_audit

qa_clean=$(fixture qa-clean.out <<'EOF'
26 queue issues checked across 9 repositories, 0 flagged.

No primary checkout carries uncommitted tracked changes.

No worktree carries uncommitted tracked changes.

Every ADR file has a row in docs/adr/README.md.
EOF
)
assert_eq "queue-audit: clean" "CLEAN" "$(classify_queue_audit "$qa_clean")"

qa_flagged=$(fixture qa-flagged.out <<'EOF'
MISSING  23-56  (ago-root#622) - queue issue names an item with no backlog file
26 queue issues checked across 9 repositories, 1 flagged.

No primary checkout carries uncommitted tracked changes.

No worktree carries uncommitted tracked changes.

Every ADR file has a row in docs/adr/README.md.
EOF
)
assert_eq "queue-audit: flagged count above zero" "FINDING" "$(classify_queue_audit "$qa_flagged")"

qa_uncommitted_primary=$(fixture qa-uncommitted-primary.out <<'EOF'
26 queue issues checked across 9 repositories, 0 flagged.

UNCOMMITTED  C:/git/ago/ago-root (on main) carries tracked changes:
             M docs/backlog/25-03-foo.md
             This belongs in a worktree. It is on no branch, and the next pull or checkout here destroys it.

No worktree carries uncommitted tracked changes.

Every ADR file has a row in docs/adr/README.md.
EOF
)
assert_eq "queue-audit: dirty primary checkout, flagged still zero" "FINDING" "$(classify_queue_audit "$qa_uncommitted_primary")"

qa_open_worktree=$(fixture qa-open-worktree.out <<'EOF'
26 queue issues checked across 9 repositories, 0 flagged.

No primary checkout carries uncommitted tracked changes.

Uncommitted work in a worktree, for an item that is still OPEN:
  C:/git/ago/ago-root-22-29  (22-29 is open)
       M tools/queue-audit.sh
  This exists nowhere else. It is on no branch and in no commit, so nothing else can see it -
  not this script's other checks, not `git log --grep`, not CI, not the board.

Every ADR file has a row in docs/adr/README.md.
EOF
)
assert_eq "queue-audit: uncommitted work in an open item's worktree" "FINDING" "$(classify_queue_audit "$qa_open_worktree")"

qa_missing_adr=$(fixture qa-missing-adr.out <<'EOF'
26 queue issues checked across 9 repositories, 0 flagged.

No primary checkout carries uncommitted tracked changes.

No worktree carries uncommitted tracked changes.

ADR files with no row in docs/adr/README.md:
  0146  (0146-a-tenants-consent-acceptances-screen-omits-the-ip-and-user-agent.md)
  Add the row in the next ago-root change. An ADR outside the index is a decision that
  cannot be found by anyone reading the decisions as a set.
EOF
)
assert_eq "queue-audit: ADR missing its index row" "FINDING" "$(classify_queue_audit "$qa_missing_adr")"

qa_cannot=$(fixture qa-cannot.out <<'EOF'
CANNOT AUDIT ago-console - could not read issues from GitHub:
  HTTP 502 (gh api error)
26 queue issues checked across 9 repositories, 0 flagged.

1 repository could NOT be read.
This is NOT a clean queue - it is a partly unread one. Re-run when GitHub answers.

No primary checkout carries uncommitted tracked changes.

No worktree carries uncommitted tracked changes.

Every ADR file has a row in docs/adr/README.md.
EOF
)
assert_eq "queue-audit: a repository could not be read" "CANNOT-LOOK" "$(classify_queue_audit "$qa_cannot")"

qa_truncated=$(fixture qa-truncated.out <<'EOF'
MISSING  23-56  (ago-root#622) - queue issue names an item with no backlog file
EOF
)
assert_eq "queue-audit: output truncated, no summary line at all" "CANNOT-LOOK" "$(classify_queue_audit "$qa_truncated")"

# -------------------------------------------------------------------------- classify_secrets_audit

assert_eq "secrets-audit: exit 0" "CLEAN" "$(classify_secrets_audit 0)"
assert_eq "secrets-audit: exit 1" "FINDING" "$(classify_secrets_audit 1)"
assert_eq "secrets-audit: exit 2 (ago-deploy missing)" "CANNOT-LOOK" "$(classify_secrets_audit 2)"
assert_eq "secrets-audit: unexpected exit code (killed, crashed, ...)" "CANNOT-LOOK" "$(classify_secrets_audit 130)"

# ----------------------------------------------------------------------- classify_tenant_isolation

ti_entry_clean=$(fixture ti-entry-clean.out <<'EOF'
Handler.cs files under UseCases: 138
Entry points found:        151
Handler classes:           138
Approx RBAC-gated:         97
Listed in exemptions:      54
Unaccounted (neither):     0
Exempt but approx-gated:   0
Exemption keys not found in scan (renamed/removed?): 0
Total exemption entries in TenantScopeExemptions.cs: 54
EOF
)
ti_routes_clean=$(fixture ti-routes-clean.out <<'EOF'
Raw Map* calls resolved: 126
Counted HTTP routes: 125
Client-supplied siteId routes: 61
TOTAL routes+hub methods (row 4): 142
TOTAL client-supplied siteId routes (row 5): 61
EOF
)
assert_eq "tenant-isolation: clean" "CLEAN" \
  "$(classify_tenant_isolation 0 "$ti_entry_clean" 0 "$ti_routes_clean")"

ti_entry_unaccounted=$(fixture ti-entry-unaccounted.out <<'EOF'
Entry points found:        152
Handler classes:           139
Approx RBAC-gated:         97
Listed in exemptions:      54
Unaccounted (neither):     1
Exempt but approx-gated:   0
Exemption keys not found in scan (renamed/removed?): 0
Total exemption entries in TenantScopeExemptions.cs: 54
EOF
)
assert_eq "tenant-isolation: one unaccounted entry point" "FINDING" \
  "$(classify_tenant_isolation 0 "$ti_entry_unaccounted" 0 "$ti_routes_clean")"

ti_entry_mismatch=$(fixture ti-entry-mismatch.out <<'EOF'
Entry points found:        151
Handler classes:           138
Approx RBAC-gated:         97
Listed in exemptions:      54
Unaccounted (neither):     0
Exempt but approx-gated:   1
Exemption keys not found in scan (renamed/removed?): 0
Total exemption entries in TenantScopeExemptions.cs: 54
EOF
)
assert_eq "tenant-isolation: exempt-listed but also looks gated" "FINDING" \
  "$(classify_tenant_isolation 0 "$ti_entry_mismatch" 0 "$ti_routes_clean")"

ti_entry_stale_exemption=$(fixture ti-entry-stale-exemption.out <<'EOF'
Entry points found:        150
Handler classes:           138
Approx RBAC-gated:         97
Listed in exemptions:      53
Unaccounted (neither):     0
Exempt but approx-gated:   0
Exemption keys not found in scan (renamed/removed?): 1
Total exemption entries in TenantScopeExemptions.cs: 54
EOF
)
assert_eq "tenant-isolation: exemption key no longer found in the scan" "FINDING" \
  "$(classify_tenant_isolation 0 "$ti_entry_stale_exemption" 0 "$ti_routes_clean")"

assert_eq "tenant-isolation: scan_entry_points.py crashed" "CANNOT-LOOK" \
  "$(classify_tenant_isolation 1 "$ti_entry_clean" 0 "$ti_routes_clean")"

assert_eq "tenant-isolation: scan_routes.py crashed" "CANNOT-LOOK" \
  "$(classify_tenant_isolation 0 "$ti_entry_clean" 1 "$ti_routes_clean")"

ti_entry_garbled=$(fixture ti-entry-garbled.out <<'EOF'
Traceback (most recent call last):
  File "scan_entry_points.py", line 40, in main
IndexError: list index out of range
EOF
)
assert_eq "tenant-isolation: output shape changed, no counters to read" "CANNOT-LOOK" \
  "$(classify_tenant_isolation 0 "$ti_entry_garbled" 0 "$ti_routes_clean")"

# NOTE ON WHAT IS DELIBERATELY NOT TESTED HERE: a drifted headline number in tenant-isolation.md
# against what the scan reports (e.g. this fixture's own 151 vs the document's own last-known 134)
# is not a FINDING by design - see classify_tenant_isolation's comment in
# run-loss-and-forgot-checks.sh. There is no test asserting that here because there is no code path
# that reads the document at all; the absence is the point, not an oversight.

# --------------------------------------------------------------------------------------- summary

echo
echo "$PASS passed, $FAIL failed."
[ "$FAIL" = 0 ]
