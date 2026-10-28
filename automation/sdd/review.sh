#!/usr/bin/env bash
# The reviewer's two mechanical halves. The agent runs in between, in its own job,
# with no checkout and no GitHub token: it only ever sees the folder built here.
#
#   review.sh prepare <issue> <sha> <out-dir>   build spec.md, issue.md, diff.patch
#   review.sh publish <issue> <pr> <sha> <dir>  post the verdict, set the status
#
# Env: GH_TOKEN, GH_REPO

set -euo pipefail
source "$(dirname "$0")/lib.sh"

status() { # <sha> <state> <description>
  gh api "repos/$GH_REPO/statuses/$1" -f state="$2" -f context=verdict \
    -f description="${3:0:139}" --silent
}

prepare() {
  local n="$1" sha="$2" out="$3" ctx
  status "$sha" pending "Reviewer running"
  mkdir -p "$out"
  git_auth fetch -q origin "$DEFAULT_BRANCH"
  git diff "origin/$DEFAULT_BRANCH...$sha" > "$out/diff.patch"
  ctx=$(issue_context "$n")
  jq -r '"# #'"$n"' — " + .title + "\n\n" + .body' <<<"$ctx" > "$out/issue.md"
  jq -r '.parent.body // "No parent epic found."' <<<"$ctx" > "$out/spec.md"
  cp "$SDD_DIR/../../AGENTS.md" "$out/AGENTS.md"
  cp "$SDD_DIR/prompts/reviewer.md" "$out/prompt.md"
  cp "$SDD_DIR/run-agent.sh" "$out/run-agent.sh"
}

publish() {
  local n="$1" pr="$2" sha="$3" dir="$4" verdict first state
  verdict="$dir/verdict.md"
  first=$(head -n 1 "$verdict" 2>/dev/null || true)
  if [ "$first" = "Verdict: pass" ]; then
    state=success
  elif [[ "$first" == "Verdict: fail"* ]]; then
    state=failure
  else
    state=failure
    first="Verdict: fail — the reviewer gave no valid verdict"
    { echo "$first"; echo; cat "$verdict" 2>/dev/null || true; } > "$verdict.tmp" && mv "$verdict.tmp" "$verdict"
  fi
  gh pr comment "$pr" --body-file "$verdict"
  status "$sha" "$state" "$first"
  echo "state=$state" >> "$GITHUB_OUTPUT"
  log "issue #$n: $first"
}

cmd="$1"; shift
case "$cmd" in
  prepare) prepare "$@" ;;
  publish) publish "$@" ;;
  *) die "unknown command: $cmd" ;;
esac
