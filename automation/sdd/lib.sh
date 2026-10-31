#!/usr/bin/env bash
# Shared helpers for the chaski loop. Sourced by the other scripts.
# Every name used here is defined in the Names table of AGENTS.md.

set -euo pipefail

SDD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTECTED_FILE="${PROTECTED_FILE:-.github/protected-paths}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

log() { echo "sdd: $*" >&2; }
die() { echo "::error::sdd: $*" >&2; exit 1; }

loop_enabled() { [ "${LOOP_ENABLED:-false}" = "true" ]; }

# task/<n> -> <n>
issue_from_branch() {
  local ref="$1"
  [[ "$ref" =~ ^task/([0-9]+)$ ]] || die "not a task branch: $ref"
  echo "${BASH_REMATCH[1]}"
}

# Run git with the App token for one command, without writing it to git config.
git_auth() {
  local basic
  basic=$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')
  git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $basic" "$@"
}

# The "checks: #<n>" commit on HEAD that is not yet on the default branch.
find_check_commit() {
  git log --format=%H --grep="^checks: #$1\$" "origin/$DEFAULT_BRANCH..HEAD" | tail -n 1
}

# Files changed by commits on HEAD since the default branch, not merges. Extra args filter the commits.
files_since_default() {
  git log "origin/$DEFAULT_BRANCH..HEAD" --no-merges --no-renames --format= --name-only "$@" | sed '/^$/d' | sort -u
}

# 0 if the path is listed in .github/protected-paths.
is_protected() {
  local path="$1" p
  [ -f "$PROTECTED_FILE" ] || return 1
  while IFS= read -r p || [ -n "$p" ]; do
    p="${p%%#*}"
    p="$(printf '%s' "$p" | tr -d '[:space:]')"
    [ -z "$p" ] && continue
    if [[ "$p" == */ ]]; then
      [[ "$path" == "$p"* ]] && return 0
    else
      [[ "$path" == "$p" ]] && return 0
    fi
  done < "$PROTECTED_FILE"
  return 1
}

# Sub-issue numbers of an epic; fails when the list is cut off.
sub_issues() {
  gh issue view "$1" --json subIssues \
    -q 'if .subIssues.totalCount > (.subIssues.nodes | length) then error("sub-issue list is cut off") else .subIssues.nodes[].number end'
}

# "true" when the issue is open, has no open blocker, and is not held; fails when its blocker list is cut off.
ready_state() {
  gh issue view "$1" --json state,labels,blockedBy \
    -q 'if .blockedBy.totalCount > (.blockedBy.nodes | length) then error("blocker list is cut off") else .state == "OPEN" and all(.blockedBy.nodes[]; .state != "OPEN") and all(.labels[]; .name != "needs-human" and .name != "in-progress") end'
}

has_label() {
  gh issue view "$1" --json labels -q "[.labels[].name] | any(. == \"$2\")" | grep -qx true
}

open_pr_for() {
  gh pr list --head "task/$1" --state open --json number -q '.[0].number // empty'
}

# Issue title, body, and its parent epic's body, as JSON.
issue_context() {
  gh api graphql \
    -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){title body parent{number title body}}}}' \
    -f o="${GH_REPO%/*}" -f r="${GH_REPO#*/}" -F n="$1" \
    -q '.data.repository.issue'
}

# Hand an issue to a person: comment, needs-human, release the lock, stop auto-merge.
park() {
  local n="$1" msg="$2" pr
  gh issue comment "$n" --body "$msg"
  gh issue edit "$n" --add-label needs-human
  gh issue edit "$n" --remove-label in-progress >/dev/null 2>&1 || true
  pr=$(open_pr_for "$n")
  if [ -n "$pr" ]; then gh pr merge "$pr" --disable-auto >/dev/null 2>&1 || true; fi
}

# 0 when LOOP_WINDOW ("22-07") is unset or the current hour in LOOP_TZ falls inside it.
in_window() {
  [ -z "${LOOP_WINDOW:-}" ] && return 0
  local start="${LOOP_WINDOW%-*}" end="${LOOP_WINDOW#*-}" h
  h=$(TZ="${LOOP_TZ:-UTC}" date +%H)
  h=$((10#$h)); start=$((10#$start)); end=$((10#$end))
  if [ "$start" -le "$end" ]; then
    [ "$h" -ge "$start" ] && [ "$h" -lt "$end" ]
  else
    [ "$h" -ge "$start" ] || [ "$h" -lt "$end" ]
  fi
}

# --- App token, minted and refreshed by the script ---------------------------
# Installation tokens expire after an hour and a chain can run for several, so
# long jobs mint their own from SDD_APP_ID and SDD_APP_PRIVATE_KEY. The agent
# never sees either: run-agent.sh strips them from its environment.

_b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

mint_token() {
  local now header payload sig jwt inst
  now=$(date +%s)
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | _b64url)
  payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$SDD_APP_ID" | _b64url)
  sig=$(printf '%s.%s' "$header" "$payload" \
    | openssl dgst -sha256 -sign <(printf '%s\n' "$SDD_APP_PRIVATE_KEY") | _b64url)
  jwt="$header.$payload.$sig"
  inst=$(curl -fsS -H "Authorization: Bearer $jwt" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$GH_REPO/installation" | jq -r .id)
  curl -fsS -X POST -H "Authorization: Bearer $jwt" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/$inst/access_tokens" | jq -r .token
}

# Keep GH_TOKEN fresh: mint a new one once the current one is 40 minutes old.
SDD_TOKEN_AT=0
refresh_token() {
  [ -n "${SDD_APP_PRIVATE_KEY:-}" ] || return 0
  local now; now=$(date +%s)
  if [ $((now - SDD_TOKEN_AT)) -ge 2400 ]; then
    GH_TOKEN=$(mint_token); export GH_TOKEN
    SDD_TOKEN_AT=$now
  fi
}
