#!/usr/bin/env bash
# Re-runs the mechanical half of `docs/architecture/secrets.md`'s own six sweeps and reports every
# credential name the sweeps find that the file does not mention.
#
# Why this exists: `secrets.md`'s whole value is completeness, and until `24-14` nothing kept it
# complete. `personal-data.md` is named in three places that make adding a column update it; the
# secrets inventory had no equivalent, and drifted on exactly that schedule - `17-03` wrote it on
# 2026-08-27 and by 2026-09-06 it was missing a key, understating a PAT's blast radius by a third,
# and asserting that a repository with a workflow had none.
#
# It runs sweeps 1, 2, 3 and 5. Sweeps 4 and 6 are deliberately NOT here: sweep 4 looks for a
# credential-shaped *literal*, which needs a human to say whether a given string is a secret or a
# fixture, and sweep 6 reads prose in ADRs and runbooks. A script that pretended to run them would
# report a clean sweep it had not made, which is worse than not running them.
#
# Exit status: 0 when the sweeps find nothing new, 1 when they do. Run it from `ago-root`.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
DEPLOY="$WORKSPACE/ago-deploy"
INVENTORY="$ROOT/docs/architecture/secrets.md"

# Names the sweeps produce that are not secrets: the companion half of a credential pair, or a
# setting that merely sits next to one in the same `.env`. Each is listed with its reason, because
# an unexplained allow-list is how a real secret gets silently skipped one day.
NOT_SECRETS="
POSTGRES_USER POSTGRES_DB          # the role name and database name beside POSTGRES_PASSWORD
RABBITMQ_USER MINIO_ROOT_USER      # usernames beside their own passwords
KEYCLOAK_ADMIN_USER GRAFANA_ADMIN_USER
KEYCLOAK_SMTP_HOST KEYCLOAK_SMTP_PORT KEYCLOAK_SMTP_SSL KEYCLOAK_SMTP_STARTTLS KEYCLOAK_SMTP_AUTH
KEYCLOAK_SMTP_FROM KEYCLOAK_SMTP_FROM_DISPLAY_NAME KEYCLOAK_SMTP_ENVELOPE_FROM KEYCLOAK_SMTP_USER
VAR                                # the literal token in a doc comment showing \$(VAR) substitution
"
allowed() {
  printf '%s\n' $NOT_SECRETS | grep -qx "$1"
}

if [ ! -d "$DEPLOY" ]; then
  echo "ago-deploy is not beside ago-root at $DEPLOY - sweeps 1-3 cannot run." >&2
  echo "This is 'could not look', not 'nothing to see'." >&2
  exit 2
fi

found=""

# Sweep 1 - every key in the three secretGenerator sources.
for f in docker/.env.example k8s/overlays/local/.env.example k8s/overlays/demo/.env.example; do
  [ -f "$DEPLOY/$f" ] || { echo "sweep 1: $f is gone - the sweep's own source moved" >&2; continue; }
  found="$found $(grep -oE '^[A-Z0-9_]+' "$DEPLOY/$f")"
done

# Sweep 2 - every $(VAR) substitution a manifest consumes.
found="$found $(grep -rhoE '\$\([A-Z0-9_]+\)' "$DEPLOY/k8s/" | tr -d '$()')"

# Sweep 3 - every secretKeyRef key.
found="$found $(grep -rA3 'secretKeyRef' "$DEPLOY/k8s/" --include='*.yaml' \
  | grep -oE 'key: *[A-Z0-9_]+' | awk '{print $2}')"

# Sweep 5 - every secrets.* reference in every repository's workflows. Enumerated from the
# workspace rather than from a list in this file, so a new repository is swept the day it appears -
# which is the failure this whole script exists for.
repos=""
for d in "$WORKSPACE"/*/; do
  d="${d%/}"; name="$(basename "$d")"
  case "$name" in *-[0-9]*|ago-root-*|ago-business*|ago-deploy-pins) continue;; esac
  [ -d "$d/.git" ] || continue
  repos="$repos $name"
  [ -d "$d/.github/workflows" ] || continue
  found="$found $(grep -rhoE 'secrets\.[A-Z0-9_]+' "$d/.github/workflows" | cut -d. -f2)"
done

missing=""
for k in $(printf '%s\n' $found | sort -u); do
  allowed "$k" && continue
  grep -q "$k" "$INVENTORY" || missing="$missing $k"
done

echo "Swept $(printf '%s\n' $repos | wc -w | tr -d ' ') repositories:$repos"
echo

if [ -z "$missing" ]; then
  echo "Sweeps 1, 2, 3 and 5 find nothing that $INVENTORY does not already name."
  echo "Sweeps 4 and 6 are not mechanical and are not run here - see this script's own header."
  exit 0
fi

echo "These names appear in a manifest, an .env.example or a workflow, and NOT in secrets.md:"
for k in $missing; do echo "  $k"; done
echo
echo "Either add a row for each, or - if it is not a secret - add it to this script's NOT_SECRETS"
echo "list WITH its reason. An unexplained entry there is how a real secret gets skipped."
exit 1
