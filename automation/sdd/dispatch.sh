#!/usr/bin/env bash
# The orchestrator's mechanical half, as plain code: choose ready issues and lock them.
# Writes issues=<JSON array of issue numbers> to $GITHUB_OUTPUT.
# Env: GH_TOKEN, GH_REPO, LOOP_ENABLED, LOOP_WINDOW, LOOP_TZ, LOOP_MAX_PARALLEL, RUN_ISSUE
# Each picked issue starts a chain; chain.sh follows it as far as the graph allows.

set -euo pipefail
source "$(dirname "$0")/lib.sh"

emit() {
  echo "issues=$1" >> "$GITHUB_OUTPUT"
  log "dispatching: $1"
  exit 0
}

loop_enabled || { log "LOOP_ENABLED is not true"; emit '[]'; }

# A person can start one issue by hand from the Actions tab.
if [ -n "${RUN_ISSUE:-}" ]; then
  [[ "$RUN_ISSUE" =~ ^[0-9]+$ ]] || die "bad issue number: $RUN_ISSUE"
  gh issue edit "$RUN_ISSUE" --add-label in-progress
  emit "[$RUN_ISSUE]"
fi

in_window || { log "outside LOOP_WINDOW $LOOP_WINDOW ($LOOP_TZ)"; emit '[]'; }

# Red stops dispatch: the latest gate run on the default branch must be green.
main_state=$(gh run list --workflow sdd-gate.yml --branch "$DEFAULT_BRANCH" --event push --limit 1 \
  --json status,conclusion -q '.[0] | "\(.status)/\(.conclusion)"')
case "$main_state" in
  ""|"null/null"|"completed/success") ;;
  *) log "$DEFAULT_BRANCH is not green ($main_state)"; emit '[]' ;;
esac

max="${LOOP_MAX_PARALLEL:-2}"
busy=$(gh issue list --label in-progress --state open --limit 500 --json number -q 'length')
slots=$((max - busy))
[ "$slots" -gt 0 ] || { log "no free slots ($busy of $max busy)"; emit '[]'; }

picked=()
for epic in $(gh issue list --label epic --state open --limit 200 --json number -q '.[].number'); do
  for n in $(gh issue view "$epic" --json subIssues -q '.subIssues[].number'); do
    [ "${#picked[@]}" -ge "$slots" ] && break 2
    state=$(gh issue view "$n" --json state -q .state)
    [ "$state" = "OPEN" ] || continue
    blockers=$(gh issue view "$n" --json blockedBy -q '[.blockedBy[] | select(.state=="OPEN")] | length')
    [ "$blockers" -eq 0 ] || continue
    held=$(gh issue view "$n" --json labels -q '[.labels[].name] | any(. == "needs-human" or . == "in-progress")')
    [ "$held" = "false" ] || continue
    if ! git_auth ls-remote --exit-code --heads "https://github.com/$GH_REPO.git" "task/$n" >/dev/null; then
      park "$n" "No \`task/$n\` branch with checks yet. Commit the checks for this issue as the branch's first commit (\`checks: #$n\`), then remove \`needs-human\`."
      continue
    fi
    gh issue edit "$n" --add-label in-progress
    picked+=("$n")
  done
done

if [ "${#picked[@]}" -eq 0 ]; then emit '[]'; fi
emit "$(printf '%s\n' "${picked[@]}" | jq -R 'tonumber' | jq -cs .)"
