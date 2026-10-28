#!/usr/bin/env bash
# One implementer session working a chain of tasks, starting at <issue>.
#
# For each task:
#   1. Bring task/<n> up to date with the default branch.
#   2. Run the agent (resuming the chain's session after the first task).
#   3. Push, open or update the PR with the report, turn on auto-merge.
#   4. Wait for the task's own evidence: gate, verdict, merge.
#      A failure gets one retry in the same session; a second failure parks it.
#   5. After the merge, continue to the next task in the chain while the
#      session has room, the job has time, and the window is open.
#
# A chain is a run of tasks, each blocked only by the one before it. It ends
# where the graph branches or joins; dispatch hands those tasks to other agents.
#
# Usage: chain.sh <issue>
# Env: GH_REPO, SDD_APP_ID, SDD_APP_PRIVATE_KEY (or GH_TOKEN), TEST_COMMAND,
#      MERGE_METHOD, CHAIN_MAX_TASKS, CHAIN_MAX_CONTEXT, CHAIN_TIMEOUT_MINUTES,
#      CHAIN_TASK_RESERVE_MINUTES, WAIT_MINUTES, LOOP_WINDOW, LOOP_TZ,
#      SDD_GIT_NAME, SDD_GIT_EMAIL

set -euo pipefail
source "$(dirname "$0")/lib.sh"

started=$(date +%s)
max_tasks="${CHAIN_MAX_TASKS:-5}"
max_context="${CHAIN_MAX_CONTEXT:-0.6}"
job_minutes="${CHAIN_TIMEOUT_MINUTES:-300}"
reserve_minutes="${CHAIN_TASK_RESERVE_MINUTES:-60}"
wait_minutes="${WAIT_MINUTES:-45}"

work="${RUNNER_TEMP:-/tmp}/sdd-chain"
mkdir -p "$work" 2>/dev/null || true
state="$work/current-issue"     # read by the workflow's cleanup step
usage="$work/usage.json"
session=$(cat /proc/sys/kernel/random/uuid)
session_started=false
last_cost=0


# --- helpers -----------------------------------------------------------------

elapsed_minutes() { echo $(( ($(date +%s) - started) / 60 )); }

prepare_branch() { # <n> -> sets check, conflicts
  local n="$1"
  git_auth fetch -q origin "$DEFAULT_BRANCH" "task/$n"
  git checkout -q -B "task/$n" "origin/task/$n"
  check=$(find_check_commit "$n")
  conflicts=no
  if [ -n "$check" ]; then
    git merge -q --no-edit "origin/$DEFAULT_BRANCH" || conflicts=yes
  fi
}

context_block() { # <n> <report> <question>
  local n="$1" ctx
  ctx=$(issue_context "$n")
  title=$(jq -r '.title' <<<"$ctx")
  cat <<EOF
## Context

- Issue: #$n — $title
- Branch: task/$n, already checked out
- Checks commit: $check
- Test command: ${TEST_COMMAND:-not set; find the project test command}
- Unresolved merge conflicts with $DEFAULT_BRANCH: $conflicts
- Report path: $2
- Question path: $3

### Sub-issue #$n

$(jq -r '.body' <<<"$ctx")

### Epic spec

$(jq -r '.parent.body // "No parent epic found."' <<<"$ctx")
EOF
}

run_agent() { # <prompt-file>
  local resume=false
  if [ "$session_started" = "true" ]; then resume=true; fi
  AGENT_SESSION_ID="$session" AGENT_RESUME="$resume" AGENT_USAGE_FILE="$usage" \
    "$SDD_DIR/run-agent.sh" implementer "$1" "$PWD"
  session_started=true
}

# Push the agent's work and make sure a PR with auto-merge exists. -> sets pr
publish() { # <n> <report>
  local n="$1" report="$2" cost delta ctx_tokens ctx_window run_line
  [ -z "$(git ls-files -u)" ] || die "merge conflicts left unresolved"
  if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -q -m "task #$n: implementer changes"
  fi
  if ! grep -q "Closes #$n" "$report"; then
    { echo "Closes #$n"; echo; cat "$report"; } > "$report.tmp" && mv "$report.tmp" "$report"
  fi

  # The run line is the script's, not the agent's: cost for this task and the
  # session's context, from what the CLI reported.
  cost=$(jq -r '.cost_usd // empty' "$usage" 2>/dev/null || true)
  ctx_tokens=$(jq -r '.context_tokens // empty' "$usage" 2>/dev/null || true)
  ctx_window=$(jq -r '.context_window // empty' "$usage" 2>/dev/null || true)
  run_line="Session \`${session:0:8}\`, task $tasks_done of up to $max_tasks"
  if [ -n "$cost" ]; then
    delta=$(jq -n --argjson c "$cost" --argjson l "$last_cost" '($c - $l) * 100 | round / 100')
    run_line+=", cost \$$delta"
    last_cost="$cost"
  fi
  if [ -n "$ctx_tokens" ] && [ -n "$ctx_window" ]; then
    run_line+=", context $(jq -n --argjson t "$ctx_tokens" --argjson w "$ctx_window" '$t * 100 / $w | round')%"
  fi
  printf '\n### Run\n- %s\n' "$run_line" >> "$report"

  refresh_token
  git_auth push -q origin "HEAD:task/$n"
  pr=$(open_pr_for "$n")
  if [ -n "$pr" ]; then
    gh pr edit "$pr" --body-file "$report"
  else
    gh pr create --base "$DEFAULT_BRANCH" --head "task/$n" --title "$title" --body-file "$report" >/dev/null
    pr=$(open_pr_for "$n")
  fi
  gh pr merge "$pr" --auto "--${MERGE_METHOD:-squash}"
}

# Wait for the task's evidence. Prints: merged | parked | stalled | failed:gate | failed:verdict
wait_outcome() { # <n> <pr>
  local n="$1" pr="$2" deadline passed_at="" json pr_state gate verdict
  deadline=$(( $(date +%s) + wait_minutes * 60 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep 30
    refresh_token
    if has_label "$n" needs-human; then echo parked; return; fi
    json=$(gh pr view "$pr" --json state,statusCheckRollup)
    pr_state=$(jq -r '.state' <<<"$json")
    if [ "$pr_state" = "MERGED" ]; then echo merged; return; fi
    gate=$(jq -r '[.statusCheckRollup[] | select((.name // .context) == "gate") | (if (.conclusion // "") != "" then .conclusion else (.state // "PENDING") end)] | last // "PENDING"' <<<"$json")
    verdict=$(jq -r '[.statusCheckRollup[] | select((.name // .context) == "verdict") | (if (.conclusion // "") != "" then .conclusion else (.state // "PENDING") end)] | last // "PENDING"' <<<"$json")
    case "$gate" in FAILURE|ERROR|CANCELLED|TIMED_OUT|ACTION_REQUIRED) echo failed:gate; return ;; esac
    case "$verdict" in FAILURE|ERROR) echo failed:verdict; return ;; esac
    if [ "$gate" = "SUCCESS" ] && [ "$verdict" = "SUCCESS" ]; then
      passed_at="${passed_at:-$(date +%s)}"
      # Both checks green but no merge after ten minutes: something else holds it.
      if [ $(( $(date +%s) - passed_at )) -ge 600 ]; then echo stalled; return; fi
    fi
  done
  echo stalled
}

# What failed, for the retry prompt: the failed gate log or the verdict.
failure_details() { # <pr> <gate|verdict>
  local pr="$1" kind="$2" run_id
  if [ "$kind" = "gate" ]; then
    run_id=$(gh pr view "$pr" --json statusCheckRollup \
      -q '[.statusCheckRollup[] | select(.name == "gate") | .detailsUrl] | last // ""' \
      | sed -n 's#.*/actions/runs/\([0-9]*\).*#\1#p')
    if [ -n "$run_id" ]; then gh run view "$run_id" --log-failed 2>/dev/null | tail -n 80 || true; fi
  else
    gh pr view "$pr" --json comments \
      -q '[.comments[].body | select(startswith("Verdict:"))] | last // ""'
  fi
}

# The single next task in the chain, if there is exactly one. -> prints n or nothing
next_in_chain() { # <n>
  local n="$1" epic m found="" count=0 all open held
  epic=$(issue_context "$n" | jq -r '.parent.number // empty')
  [ -n "$epic" ] || return 0
  for m in $(gh issue view "$epic" --json subIssues -q '.subIssues[].number'); do
    [ "$(gh issue view "$m" --json state -q .state)" = "OPEN" ] || continue
    all=$(gh issue view "$m" --json blockedBy -q '[.blockedBy[].number] | map(tostring) | join(",")')
    if [ "$all" = "$n" ]; then found="$m"; count=$((count + 1)); fi
  done
  # More than one successor means the graph branches: the chain ends, dispatch takes them.
  [ "$count" -eq 1 ] || return 0
  open=$(gh issue view "$found" --json blockedBy -q '[.blockedBy[] | select(.state=="OPEN")] | length')
  held=$(gh issue view "$found" --json labels -q '[.labels[].name] | any(. == "needs-human" or . == "in-progress")')
  [ "$open" -eq 0 ] && [ "$held" = "false" ] || return 0
  git_auth ls-remote --exit-code --heads "https://github.com/$GH_REPO.git" "task/$found" >/dev/null || return 0
  echo "$found"
}

main_green() { # <merge-sha>: wait for the gate run on that commit; 0 if green
  local sha="$1" deadline s
  deadline=$(( $(date +%s) + 20 * 60 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    s=$(gh run list --workflow sdd-gate.yml --commit "$sha" --limit 1 \
      --json status,conclusion -q '.[0] | "\(.status)/\(.conclusion)"')
    case "$s" in
      completed/success) return 0 ;;
      completed/*) return 1 ;;
    esac
    sleep 30
    refresh_token
  done
  return 1
}

room_for_another() { # 0 if the session may take one more task
  local t w
  [ "$tasks_done" -lt "$max_tasks" ] || { log "task cap reached ($max_tasks)"; return 1; }
  [ $(( job_minutes - $(elapsed_minutes) )) -ge "$reserve_minutes" ] || { log "not enough job time left"; return 1; }
  in_window || { log "outside LOOP_WINDOW"; return 1; }
  t=$(jq -r '.context_tokens // empty' "$usage" 2>/dev/null || true)
  w=$(jq -r '.context_window // empty' "$usage" 2>/dev/null || true)
  if [ -n "$t" ] && [ -n "$w" ]; then
    if jq -e -n --argjson t "$t" --argjson w "$w" --argjson m "$max_context" '$t / $w >= $m' >/dev/null; then
      log "context at $t of $w tokens; ending the session"
      return 1
    fi
  fi
  return 0
}

# --- one task ----------------------------------------------------------------

# Returns 0 when the task merged, 1 when the chain should stop.
work_task() { # <n>
  local n="$1" report="$work/report-$1.md" question="$work/question-$1.md"
  local prompt="$work/prompt-$1.md" outcome kind attempt=1
  echo "$n" > "$state"
  rm -f "$report" "$question"

  prepare_branch "$n"
  if [ -z "$check" ]; then
    park "$n" "\`task/$n\` has no \`checks: #$n\` commit. Add the checks as the branch's first commit, then remove \`needs-human\`."
    return 1
  fi

  if [ "$session_started" = "true" ]; then
    {
      echo "Your previous task merged. The next task in your chain follows; it is a new sub-issue on a new branch."
      echo "Everything you learned about this repository still holds. The rules of AGENTS.md still apply; write a new report and, if needed, a new question at the paths below."
      echo
      context_block "$n" "$report" "$question"
    } > "$prompt"
  else
    { cat "$SDD_DIR/prompts/implementer.md"; echo; context_block "$n" "$report" "$question"; } > "$prompt"
  fi

  while :; do
    run_agent "$prompt"
    if [ -s "$question" ]; then
      park "$n" "**The implementer has a question**"$'\n\n'"$(cat "$question")"$'\n\n'"Answer here, then remove \`needs-human\`."
      return 1
    fi
    [ -s "$report" ] || die "the implementer wrote no report for #$n"
    publish "$n" "$report"

    outcome=$(wait_outcome "$n" "$pr")
    log "#$n: $outcome"
    case "$outcome" in
      merged) return 0 ;;
      parked) return 1 ;;
      stalled)
        park "$n" "PR #$pr did not merge within the wait. Check its status checks and auto-merge, then remove \`needs-human\`."
        return 1 ;;
      failed:*)
        kind="${outcome#failed:}"
        if [ "$attempt" -ge 2 ]; then
          park "$n" "The second attempt failed its \`$kind\` check. Answer here, then remove \`needs-human\` to return it."
          return 1
        fi
        attempt=2
        rm -f "$report"
        {
          echo "Your PR #$pr for #$n failed its \`$kind\` check. What failed:"
          echo
          echo '```'
          failure_details "$pr" "$kind"
          echo '```'
          echo
          echo "Fix it on the same branch, task/$n, which is still checked out. Do not change the checks."
          echo "Write a fresh report to $report, or a question to $question if this needs a person."
        } > "$prompt"
        ;;
    esac
  done
}

# --- the chain ---------------------------------------------------------------

run_chain() {
  refresh_token
  git config user.name "${SDD_GIT_NAME:-sdd-agent}"
  git config user.email "${SDD_GIT_EMAIL:-sdd-agent@users.noreply.github.com}"

  n="$1"
  tasks_done=0
  while :; do
    tasks_done=$((tasks_done + 1))
    work_task "$n" || break
    room_for_another || break
    # Claim the next task right away, before dispatch sees the merge.
    # The merge closes #n a few seconds after it lands; give the graph a moment.
    next=""
    for _ in 1 2 3; do
      next=$(next_in_chain "$n")
      [ -n "$next" ] && break
      sleep 15
    done
    [ -n "$next" ] || { log "chain ends after #$n"; break; }
    gh issue edit "$next" --add-label in-progress
    echo "$next" > "$state"
    merge_sha=$(gh pr view "$pr" --json mergeCommit -q '.mergeCommit.oid')
    if ! main_green "$merge_sha"; then
      log "$DEFAULT_BRANCH is not green after #$n; ending the chain"
      gh issue edit "$next" --remove-label in-progress >/dev/null 2>&1 || true
      break
    fi
    log "continuing the chain: #$n -> #$next"
    n="$next"
  done
  rm -f "$state"
  log "session ${session:0:8} finished after $tasks_done task(s)"
}

# Run when executed; only define functions when sourced (for tests).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then run_chain "$1"; fi
