#!/usr/bin/env bash
# The mechanical guards of the gate, for task branches.
#   - Fails if an implementer commit touched a file the checks commit added.
#   - Lists implementer-touched protected paths in the `protected` output.
# Usage: gate-checks.sh <task-branch>
# Env: GITHUB_OUTPUT

set -euo pipefail
source "$(dirname "$0")/lib.sh"

n=$(issue_from_branch "$1")
check=$(find_check_commit "$n")
[ -n "$check" ] || die "no 'checks: #$n' commit on task/$n; the checks must be the branch's first commit"

check_files=$(git diff-tree --no-commit-id --name-only -r "$check" | sort -u)
changed=$(implementer_commits "$check" | files_in_commits)

touched_checks=$(comm -12 <(printf '%s\n' "$check_files") <(printf '%s\n' "$changed") | sed '/^$/d' || true)

protected=""
while IFS= read -r f; do
  [ -n "$f" ] && is_protected "$f" && protected+="$f "
done <<< "$changed"

echo "protected=${protected% }" >> "$GITHUB_OUTPUT"

if [ -n "$touched_checks" ]; then
  die "implementer commits changed the checks: $(echo "$touched_checks" | tr '\n' ' ')"
fi
log "checks unchanged for #$n${protected:+; protected paths touched: $protected}"
