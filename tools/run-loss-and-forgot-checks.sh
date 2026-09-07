#!/usr/bin/env bash
# 25-03: runs the three "loss and forgot" checks - queue-audit.sh, secrets-audit.sh and
# tools/tenant-isolation-scan/ - on a schedule (twice a day, from Windows Task Scheduler; see
# docs/runbooks/loss-and-forgot-checks.md for registration), and tells a person only when one of
# them finds something or could not look. All three already existed and had already caught real
# drift before this was written; nothing called any of them (docs/backlog/25-03-*.md).
#
# Design, load-bearing:
#
#   - QUIET ON CLEAN, LOUD OTHERWISE. The author's own instruction (25-03, 2026-09-06): "главное
#     здесь - исправить, мне не важно, что было неправильно, если исправил" - fix it, the report
#     doesn't matter. A mailer that fires twice a day regardless trains its reader to filter it,
#     which manufactures the exact habit an alert exists to prevent. So this script sends nothing
#     on a clean run, and something short and actionable otherwise.
#
#   - "COULD NOT LOOK" IS NOT "CLEAN". Silence must mean "nothing to see", never "the check did
#     not run" or "the check ran and could not reach its source". `queue-audit.sh` already makes
#     this distinction for its own GitHub reads (its `CANNOT AUDIT` lines); this wrapper has to
#     preserve it end to end, or wrapping the three scripts reintroduces, one level up, the exact
#     failure they exist to catch - a green line from a check that did not actually look. See
#     classify_secrets_audit's ago-deploy freshening step for a second instance of the same care.
#
#   - EVERYTHING RUNS ON THIS MACHINE, NOT IN CI. `queue-audit.sh`'s worktree-and-primary-checkout
#     scan reads local disk state a GitHub-hosted runner cannot see at all - `docs/backlog/25-03-*`
#     names this as the deciding constraint, and its own open question weighs splitting the other
#     two checks into a GitHub Actions workflow against keeping all three here. Splitting was
#     decided against: it is a third shape that costs two places to look (the item's own words) for
#     no offsetting gain, since all three checks already need a local, sibling-repository workspace
#     laid out exactly as `docs/runbooks/workspace.md` describes it, and a hosted runner would need
#     its own credential for outbound mail besides. `ago-root` stays without CI for this reason,
#     not by oversight.
#
#   - EMAIL REUSES adr/0045; IT DOES NOT INVENT A NEW SENDER. This deployment already has exactly
#     one path from a condition to a person's inbox: the node's own Postfix, zero credential,
#     addressed to `alerts@reserve-me.ru` (adr/0045), already carrying real traffic today from
#     `ago-deploy/k8s/backup/backup-watchdog.sh`. `adr/0040` had, one day earlier, already weighed a
#     hosted mail provider against self-hosting and ruled out every third party - payment
#     (Russian-issued cards do not clear at Western vendors, `adr/0026`) and data-residency reasons
#     that apply to this script exactly as they applied there. So reusing that path is not a
#     default this script picked; it is what the standing decision already requires, and inventing
#     a second sender (a hosted API, a bot token) would need a secret this deployment does not
#     carry and would quietly re-litigate a decision that was not this item's to reopen. This
#     script reaches that Postfix the same way a person reaches the node to run `backup.sh` by hand
#     (`docs/runbooks/backup-and-restore.md`) - over SSH, with the same key - because nothing on
#     this Windows machine can otherwise address a Postfix that only accepts mail from the k3s
#     bridge or from `localhost` on the node itself.
#
#   - TWO INDEPENDENT WAYS TO SEE "DID THIS RUN", NEITHER OF THEM AN EMAIL. A quiet-on-clean design
#     cannot use the mailbox to answer "is this still running at all" - a stopped scheduler and a
#     clean sweep both produce silence there, which is exactly the failure this item's own brief
#     warns about. Two things exist instead, deliberately outside the mailbox: this run's exit code
#     (0 clean, 1 a check found something, 2 a check could not look - secrets-audit.sh's own
#     convention, widened to the whole sweep), which Windows Task Scheduler records as "Last Run
#     Result" for every trigger whether or not anything fired; and one line appended to
#     `<workspace>/loss-and-forgot-history.log` on every run, clean or not - a file this repository
#     does not track, sitting beside the checkouts the way `.nuget-feed` does
#     (`docs/runbooks/workspace.md`). Reading either answers "did it run" without depending on the
#     inbox. Neither is pushed to a person the way GitHub's own scheduled-workflow-disabled email
#     would have been had this run as a workflow instead - see the runbook for what that residual
#     gap is and why it was accepted rather than hidden.
#
# Usage: bash tools/run-loss-and-forgot-checks.sh [--dry-run]
#   --dry-run   compose the message and print it instead of mailing it (sets
#               LOSS_AND_FORGOT_DRY_RUN=1). The three checks still run for real; only delivery is
#               stubbed. Useful for demonstrating the classification without touching the node.
#
# Env overrides: AGO_NODE (required for a real send - the node's address; never written here, see
# CLAUDE.md), LOSS_AND_FORGOT_DRY_RUN=1 (same as --dry-run), LOSS_AND_FORGOT_LOG (heartbeat path,
# default <workspace>/loss-and-forgot-history.log).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"

# ---------------------------------------------------------------------------------------------
# Classification. Each function is pure - given captured output (and, where the wrapped script is
# honest about it, an exit code), it returns exactly one of CLEAN / FINDING / CANNOT-LOOK on
# stdout. Kept separate from the run_* functions below (which do the actual freshening and
# invoking) so tools/run-loss-and-forgot-checks.test.sh can exercise the classification against
# canned fixtures without running git, ssh, or the real checks at all.
# ---------------------------------------------------------------------------------------------

# queue-audit.sh always exits 0 - "flagged entries are for a human to resolve... a CI job that
# failed on this would train people to close issues to make it green" (its own comment). So the
# signal is textual, not the exit code, and has to cover every shape a finding takes in that
# script: the summary line's own flagged count, an uncommitted primary checkout, uncommitted work
# in a worktree for a still-open item, and a missing ADR index row - none of which feed the same
# counter as the others.
classify_queue_audit() {  # $1 = path to captured combined stdout+stderr
  local out="$1"
  if grep -q '^CANNOT AUDIT' "$out" || grep -q 'could NOT be read' "$out"; then
    echo CANNOT-LOOK
    return
  fi
  local flagged
  flagged=$(grep -oE ', [0-9]+ flagged\.' "$out" | grep -oE '[0-9]+' | head -1 || true)
  if [ -z "$flagged" ]; then
    # The summary line itself is missing - the script's output shape changed, or it did not run to
    # completion. Either way this run cannot vouch for "clean", so it is not reported as one.
    echo CANNOT-LOOK
    return
  fi
  if [ "$flagged" != "0" ]; then echo FINDING; return; fi
  if grep -q '^UNCOMMITTED' "$out"; then echo FINDING; return; fi
  if grep -q 'for an item that is still OPEN:' "$out"; then echo FINDING; return; fi
  if grep -q '^ADR files with no row' "$out"; then echo FINDING; return; fi
  echo CLEAN
}

# secrets-audit.sh's own exit codes already make this distinction (0 clean, 1 finding, 2 could not
# look - "sweeps 1-3 cannot run") - see its own header. Nothing to add here.
classify_secrets_audit() {  # $1 = exit code
  case "$1" in
    0) echo CLEAN ;;
    1) echo FINDING ;;
    *) echo CANNOT-LOOK ;;
  esac
}

# Neither scan script sets an exit code of its own (see tools/tenant-isolation-scan/README.md -
# both are read-only re-derivations, not gates). scan_entry_points.py does carry its own
# correctness signal though: Unaccounted / "exempt but also looks gated" / exemption keys the scan
# can no longer find are real findings TenantScopeTests would also catch. A drifted headline number
# in tenant-isolation.md against what the scan reports is deliberately NOT one of them - that
# drift is real (see 24-17) and is 24-17's mechanism to fix, not this item's to detect a second
# way; treating it as a finding here would mail on it every twelve hours until 24-17 lands, which
# is exactly the alert-fatigue failure this item's brief warns against, for a condition this item
# was explicitly told is out of scope.
classify_tenant_isolation() {  # $1 entry_exit $2 entry_out $3 routes_exit $4 routes_out
  local entry_exit="$1" entry_out="$2" routes_exit="$3" routes_out="$4"
  if [ "$entry_exit" != "0" ] || [ "$routes_exit" != "0" ]; then echo CANNOT-LOOK; return; fi
  if ! grep -q '^Unaccounted (neither):' "$entry_out"; then echo CANNOT-LOOK; return; fi
  if ! grep -q '^TOTAL client-supplied siteId routes' "$routes_out"; then echo CANNOT-LOOK; return; fi
  local unacc mismatch missing
  unacc=$(grep -oE '^Unaccounted \(neither\): *[0-9]+' "$entry_out" | grep -oE '[0-9]+$' || true)
  mismatch=$(grep -oE '^Exempt but approx-gated: *[0-9]+' "$entry_out" | grep -oE '[0-9]+$' || true)
  missing=$(grep -oE '^Exemption keys not found in scan.*: *[0-9]+' "$entry_out" | grep -oE '[0-9]+$' || true)
  if [ "${unacc:-0}" != "0" ] || [ "${mismatch:-0}" != "0" ] || [ "${missing:-0}" != "0" ]; then
    echo FINDING
  else
    echo CLEAN
  fi
}

# ---------------------------------------------------------------------------------------------
# Running the three checks for real. Populates *_STATUS plus the captured-output paths the
# excerpt/compose functions below read.
# ---------------------------------------------------------------------------------------------

run_queue_audit() {
  QUEUE_OUT="$SCRATCH/queue-audit.out"
  ( cd "$ROOT" && bash tools/queue-audit.sh ) >"$QUEUE_OUT" 2>&1
  QUEUE_STATUS=$(classify_queue_audit "$QUEUE_OUT")
}

# "Freshly fetched checkouts" (25-03's own scope line) means something different for each script.
# queue-audit.sh's local-disk checks (worktrees, primary-checkout dirt, the ADR index) are reading
# live state on purpose - there is no "origin/main version" of an uncommitted worktree to fetch.
# secrets-audit.sh's sweeps 1-3 read ago-deploy's manifests as files on disk, so a stale local
# checkout can print a clean sweep against content that stopped being current days ago - the exact
# "green line from a failed filter" shape this item's own brief calls out by name for a different
# check. So this repository specifically gets fetched AND fast-forwarded before the sweep runs; if
# it cannot be (dirty, diverged, or simply not there), the sweep is not trusted and this reports
# CANNOT-LOOK instead of running against unknown content. Sweep 5's other seven sibling repositories
# are read as they sit - true freshening there would mean archiving eight repositories every twelve
# hours for a category of drift (a new `secrets.NAME` in a workflow between syncs) that is both rare
# and already caught eventually by the same run once someone next builds there; that trade was made
# deliberately rather than by omission, and is recorded in the report for this item.
run_secrets_audit() {
  SECRETS_OUT="$SCRATCH/secrets-audit.out"
  : >"$SECRETS_OUT"
  local deploy="$WORKSPACE/ago-deploy"
  if [ ! -d "$deploy/.git" ]; then
    echo "ago-deploy is not beside ago-root at $deploy - cannot freshen or sweep it." >>"$SECRETS_OUT"
    SECRETS_STATUS=CANNOT-LOOK
    return
  fi
  if ! git -C "$deploy" fetch origin >>"$SECRETS_OUT" 2>&1; then
    echo "git fetch origin failed in $deploy - see above." >>"$SECRETS_OUT"
    SECRETS_STATUS=CANNOT-LOOK
    return
  fi
  if ! git -C "$deploy" merge --ff-only origin/main >>"$SECRETS_OUT" 2>&1; then
    echo "ago-deploy could not be fast-forwarded to origin/main (dirty working tree, or diverged)." >>"$SECRETS_OUT"
    echo "The sweep would run against a checkout this run cannot vouch for. Fast-forward it by hand" >>"$SECRETS_OUT"
    echo "(or resolve the divergence) and re-run." >>"$SECRETS_OUT"
    SECRETS_STATUS=CANNOT-LOOK
    return
  fi
  local exit_code
  ( cd "$ROOT" && bash tools/secrets-audit.sh ) >>"$SECRETS_OUT" 2>&1
  exit_code=$?
  SECRETS_STATUS=$(classify_secrets_audit "$exit_code")
}

# tenant-isolation-scan's own README already prescribes the safe way to point it at a specific
# ref without touching a working tree anyone might be using: `git archive` into a scratch
# directory. That also happens to be the cleanest way to satisfy "freshly fetched" here - no
# fast-forward, no dirty-checkout case to handle, always exactly origin/main.
run_tenant_isolation() {
  ENTRY_OUT="$SCRATCH/tis-entry.out"
  ROUTES_OUT="$SCRATCH/tis-routes.out"
  : >"$ENTRY_OUT"; : >"$ROUTES_OUT"
  local chat="$WORKSPACE/ago-chat"
  local archive="$SCRATCH/ago-chat-src"
  if [ ! -d "$chat/.git" ]; then
    echo "ago-chat is not beside ago-root at $chat." >>"$ENTRY_OUT"
    TENANT_STATUS=CANNOT-LOOK
    return
  fi
  if ! git -C "$chat" fetch origin >>"$ENTRY_OUT" 2>&1; then
    echo "git fetch origin failed in $chat - see above." >>"$ENTRY_OUT"
    TENANT_STATUS=CANNOT-LOOK
    return
  fi
  mkdir -p "$archive"
  if ! ( git -C "$chat" archive origin/main | tar -x -C "$archive" ) >>"$ENTRY_OUT" 2>&1; then
    echo "git archive origin/main failed in $chat - see above." >>"$ENTRY_OUT"
    TENANT_STATUS=CANNOT-LOOK
    return
  fi
  local py=python
  command -v python >/dev/null 2>&1 || py=python3
  if ! command -v "$py" >/dev/null 2>&1; then
    echo "neither python nor python3 is on PATH." >>"$ENTRY_OUT"
    TENANT_STATUS=CANNOT-LOOK
    return
  fi
  local entry_exit routes_exit
  "$py" "$ROOT/tools/tenant-isolation-scan/scan_entry_points.py" "$archive" >"$ENTRY_OUT" 2>&1
  entry_exit=$?
  "$py" "$ROOT/tools/tenant-isolation-scan/scan_routes.py" "$archive" >"$ROUTES_OUT" 2>&1
  routes_exit=$?
  TENANT_STATUS=$(classify_tenant_isolation "$entry_exit" "$ENTRY_OUT" "$routes_exit" "$ROUTES_OUT")
}

# ---------------------------------------------------------------------------------------------
# Composing and sending. Deliberately not a forensic report - the author's own words on this item
# were "не важно, что было неправильно, если исправил" (it doesn't matter what was wrong, if it
# got fixed), so the mail leads with what to do, not with completeness. queue-audit.sh's own
# "leftover, safe to remove once read" worktree list is left out of the mail on purpose for the
# same reason: it is the one section of that script's output its own text already says is not
# urgent, and a twice-daily mail is the wrong place to relitigate that.
# ---------------------------------------------------------------------------------------------

queue_excerpt() {
  awk '/^Uncommitted changes in worktrees whose item is already closed/{exit} {print}' "$QUEUE_OUT"
}

secrets_excerpt() { cat "$SECRETS_OUT"; }

tenant_excerpt() {
  echo "-- scan_entry_points.py --"
  sed -n '1,9p' "$ENTRY_OUT"
  awk '/^--- UNACCOUNTED/{p=1} /^--- EXEMPTION KEYS NOT FOUND/{p=1} p' "$ENTRY_OUT"
  echo
  echo "-- scan_routes.py --"
  grep -E '^(Counted HTTP routes|Client-supplied|TOTAL)' "$ROUTES_OUT"
}

compose_message() {
  local bits=""
  [ "$QUEUE_STATUS" != CLEAN ] && bits="$bits queue-audit"
  [ "$SECRETS_STATUS" != CLEAN ] && bits="$bits secrets-audit"
  [ "$TENANT_STATUS" != CLEAN ] && bits="$bits tenant-isolation"
  MSG_SUBJECT="[AGO] loss-and-forgot:$bits"

  MSG_BODY=$(
    echo "Sweep run at $(date -u --iso-8601=seconds) on $(hostname 2>/dev/null || echo unknown-host)."
    echo

    if [ "$QUEUE_STATUS" != CLEAN ]; then
      echo "== queue-audit.sh: $QUEUE_STATUS =="
      queue_excerpt
      echo
      echo "What to do: fix the ticket or the worktree named above, or run"
      echo "  cd <ago-root> && bash tools/queue-audit.sh"
      echo "for the rest (closed-item worktree leftovers are left out of this mail on purpose -"
      echo "the script's own text already calls them 'safe to remove once read')."
      echo
    fi

    if [ "$SECRETS_STATUS" != CLEAN ]; then
      echo "== secrets-audit.sh: $SECRETS_STATUS =="
      secrets_excerpt
      echo
      echo "What to do: add a row to docs/architecture/secrets.md, or - if it is not a secret - add"
      echo "it to secrets-audit.sh's NOT_SECRETS list with a reason."
      echo
    fi

    if [ "$TENANT_STATUS" != CLEAN ]; then
      echo "== tenant-isolation-scan: $TENANT_STATUS =="
      tenant_excerpt
      echo
      echo "What to do: an unaccounted or mismatched entry point is a real isolation gap to check by"
      echo "hand - see tools/tenant-isolation-scan/README.md. A drifted headline number in"
      echo "tenant-isolation.md against these counts is 24-17's problem, not this one's, and is not"
      echo "why this fired."
      echo
    fi

    echo "Full local record: $LOG"
    echo "Re-run by hand: cd <ago-root checkout> && bash tools/run-loss-and-forgot-checks.sh"
  )
}

# Delivery reuses adr/0045's already-proven path exactly: the node's own Postfix, reached over SSH
# with the same key `docs/runbooks/backup-and-restore.md` already uses to run backup.sh by hand,
# addressed to the same `alerts@reserve-me.ru` this repository already writes in the clear
# (`docs/runbooks/alerting.md`, `ago-deploy/k8s/backup/backup-watchdog.sh`) - the real mailbox it
# expands to lives in the node's own /etc/aliases and in no repository (CLAUDE.md).
notify() {  # $1 subject $2 body
  local subject="$1" body="$2"
  if [ "${LOSS_AND_FORGOT_DRY_RUN:-0}" = "1" ]; then
    echo "--- DRY RUN: would send mail, nothing was sent ---"
    echo "Subject: $subject"
    echo
    echo "$body"
    echo "--- end dry run ---"
    return 0
  fi
  if [ -z "${AGO_NODE:-}" ]; then
    echo "AGO_NODE is not set - refusing to guess the node's address (CLAUDE.md: no real endpoint" >&2
    echo "belongs in this repository, so it is never hardcoded here). Set AGO_NODE and re-run, or" >&2
    echo "see docs/runbooks/loss-and-forgot-checks.md." >&2
    return 1
  fi
  ssh -i ~/.ssh/ago-vps-ed25519 -o BatchMode=yes "ago@${AGO_NODE}" '/usr/sbin/sendmail -t' <<EOF
From: AGO loss-and-forgot sweep <no-reply@reserve-me.ru>
To: alerts@reserve-me.ru
Subject: ${subject}

${body}
EOF
}

record_heartbeat() {  # $1 status $2 one_line_summary
  printf '%s  %-12s %s\n' "$(date -u --iso-8601=seconds)" "$1" "$2" >>"$LOG"
}

main() {
  if [ "${1:-}" = "--dry-run" ]; then
    LOSS_AND_FORGOT_DRY_RUN=1
  fi
  LOG="${LOSS_AND_FORGOT_LOG:-$WORKSPACE/loss-and-forgot-history.log}"
  SCRATCH="$(mktemp -d)"
  trap 'rm -rf "$SCRATCH"' EXIT

  run_queue_audit
  run_secrets_audit
  run_tenant_isolation

  local summary="queue-audit=$QUEUE_STATUS secrets-audit=$SECRETS_STATUS tenant-isolation=$TENANT_STATUS"
  echo "$summary"

  local worst=CLEAN
  local s
  for s in "$QUEUE_STATUS" "$SECRETS_STATUS" "$TENANT_STATUS"; do
    [ "$s" = "CANNOT-LOOK" ] && worst=CANNOT-LOOK
  done
  if [ "$worst" != "CANNOT-LOOK" ]; then
    for s in "$QUEUE_STATUS" "$SECRETS_STATUS" "$TENANT_STATUS"; do
      [ "$s" = "FINDING" ] && worst=FINDING
    done
  fi

  if [ "$worst" = "CLEAN" ]; then
    record_heartbeat CLEAN "$summary"
    exit 0
  fi

  compose_message
  notify "$MSG_SUBJECT" "$MSG_BODY"
  record_heartbeat "$worst" "$summary"
  [ "$worst" = "FINDING" ] && exit 1
  exit 2
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
