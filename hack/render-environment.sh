#!/usr/bin/env bash
# One-shot environment render: rewrites every occurrence of the old
# environment's literals (poc.env) with the new environment's values.
#
#   hack/render-environment.sh environments/poc.env environments/prod.env
#
# Replacement runs in the key order of the OLD file — keep compound values
# (full ARNs, cluster names, URLs) above bare tokens there, or a bare token
# will clobber a compound one. Review `git diff` afterwards; that diff IS the
# migration. File CONTENTS only: files named after the service
# (envs/*/sample-api.yaml, kargo/ project files) are listed for manual rename.

set -euo pipefail

OLD_FILE="${1:?usage: render-environment.sh <old.env> <new.env>}"
NEW_FILE="${2:?usage: render-environment.sh <old.env> <new.env>}"

get() { grep -E "^$2=" "$1" | head -1 | cut -d= -f2-; }

# Ordered keys, longest/most-specific first.
KEYS=(WAF_ACL_ARN WILDCARD_CERT_ARN VPC_ID ECR_HOST GITOPS_HTTPS_URL GITOPS_SSH_URL
      KARGO_PROJECT SERVICE CLUSTER_DEV CLUSTER_STAGING DOMAIN ACCOUNT_ID REGION
      GH_OWNER SSO_ORG)

FILES=$(git ls-files | grep -vE '^(environments/|hack/)')

for key in "${KEYS[@]}"; do
  old=$(get "$OLD_FILE" "$key"); new=$(get "$NEW_FILE" "$key")
  [ -z "$old" ] && { echo "WARN: $key missing in $OLD_FILE, skipped"; continue; }
  [ -z "$new" ] && { echo "WARN: $key missing in $NEW_FILE, skipped"; continue; }
  [ "$old" = "$new" ] && continue
  count=0
  for f in $FILES; do
    if grep -qF "$old" "$f" 2>/dev/null; then
      OLD="$old" NEW="$new" perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$f"
      count=$((count+1))
    fi
  done
  echo "$key: '$old' -> '$new' in $count file(s)"
done

echo ""
echo "Files named after the old service — rename by hand:"
git ls-files | grep -F "$(get "$OLD_FILE" SERVICE)" || echo "  (none)"
echo ""
echo "Done. Review with: git diff"
