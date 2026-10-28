#!/usr/bin/env bash
# The only file that knows which agent CLI runs. Everything else calls this.
#
#   run-agent.sh --install                     install the CLI named by AGENT_CLI
#   run-agent.sh <role> <prompt-file> <dir>    run one role, headless, in <dir>
#
# Roles: implementer (edits code, runs tests) and reviewer (reads, writes verdict.md).
#
# Sessions: an implementer session is a cache and may be reused across a chain.
#   AGENT_SESSION_ID  id of the session (the caller makes one up for a new chain)
#   AGENT_RESUME      "true" to continue that session instead of starting it
# The reviewer always starts fresh and keeps no session.
#
# Usage: after each run, writes AGENT_USAGE_FILE (if set) as JSON:
#   {"cost_usd": <session total or null>, "context_tokens": <n or null>,
#    "context_window": <n or null>}
# null means the CLI did not report it; callers fall back to their task cap.
#
# Credentials: GitHub and App credentials are stripped from the agent's
# environment. The model key (ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN or
# OPENAI_API_KEY) is the only secret it receives.
#
# Env: AGENT_CLI (claude|codex), AGENT_MODEL, AGENT_MAX_TURNS, AGENT_MAX_BUDGET_USD,
#      AGENT_CONTEXT_WINDOW, AGENT_ARGS (extra flags, appended as-is)
# Flags track each CLI's documented headless mode; check them when you upgrade the CLI.

set -euo pipefail

cli="${AGENT_CLI:-claude}"

if [ "${1:-}" = "--install" ]; then
  case "$cli" in
    claude) npm install -g @anthropic-ai/claude-code ;;
    codex)  npm install -g @openai/codex ;;
    *) echo "unknown AGENT_CLI: $cli" >&2; exit 1 ;;
  esac
  exit 0
fi

role="$1" prompt_file="$2" dir="$3"
cd "$dir"
prompt="$(cat "$prompt_file")"
usage_file="${AGENT_USAGE_FILE:-/dev/null}"
resume="${AGENT_RESUME:-false}"
session="${AGENT_SESSION_ID:-}"
[ "$role" = "reviewer" ] && { resume=false; session=""; }

strip=(env -u GH_TOKEN -u GITHUB_TOKEN -u SDD_APP_PRIVATE_KEY -u SDD_APP_ID
       -u ACTIONS_RUNTIME_TOKEN -u ACTIONS_ID_TOKEN_REQUEST_TOKEN -u ACTIONS_ID_TOKEN_REQUEST_URL)

# shellcheck disable=SC2206
extra=(${AGENT_ARGS:-})

write_usage() { # <cost> <context_tokens> <context_window>
  printf '{"cost_usd": %s, "context_tokens": %s, "context_window": %s}\n' \
    "${1:-null}" "${2:-null}" "${3:-null}" > "$usage_file"
}

case "$cli" in
  claude)
    case "$role" in
      implementer) tools="Bash,Edit,Write,Read,Glob,Grep" ;;
      reviewer)    tools="Read,Write,Glob,Grep" ;;
      *) echo "unknown role: $role" >&2; exit 1 ;;
    esac
    read -r -a allowed <<< "${tools//,/ }"   # one rule per argument
    args=(-p --output-format json
          --tools "$tools"
          --allowedTools "${allowed[@]}"
          --disallowedTools "Bash(git push *)" "Bash(gh *)" "mcp__*"
          --permission-prompts none
          --max-turns "${AGENT_MAX_TURNS:-80}")
    # Bare mode skips hooks, MCP servers and settings the repository could carry.
    # It needs an API key; a subscription token runs without it.
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then args+=(--bare); fi
    if [ -z "$session" ]; then
      args+=(--no-session-persistence)
    elif [ "$resume" = "true" ]; then
      args+=(--resume "$session")
    else
      args+=(--session-id "$session")
    fi
    if [ -n "${AGENT_MODEL:-}" ]; then args+=(--model "$AGENT_MODEL"); fi
    if [ -n "${AGENT_MAX_BUDGET_USD:-}" ]; then args+=(--max-budget-usd "$AGENT_MAX_BUDGET_USD"); fi

    out="$(mktemp)"
    status=0
    "${strip[@]}" claude "${args[@]}" "${extra[@]}" -- "$prompt" > "$out" || status=$?
    jq -r '.result // empty' "$out" 2>/dev/null || cat "$out"

    cost=$(jq -r '.total_cost_usd // empty' "$out" 2>/dev/null || true)
    window=$(jq -r '[.modelUsage[]?.contextWindow // empty] | max // empty' "$out" 2>/dev/null || true)
    window="${window:-${AGENT_CONTEXT_WINDOW:-}}"
    context=""
    if [ -n "$session" ]; then
      # The transcript records each request's usage; the last one is the live context.
      transcript=$(find "$HOME/.claude/projects" -name "$session.jsonl" 2>/dev/null | head -n 1)
      if [ -n "$transcript" ]; then
        context=$(jq -s -r '[.[] | .message.usage? | select(. != null)
          | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)]
          | last // empty' "$transcript" 2>/dev/null || true)
      fi
    fi
    write_usage "$cost" "$context" "$window"
    rm -f "$out"
    exit "$status"
    ;;

  codex)
    if [ "$resume" = "true" ]; then
      args=(exec resume --last --full-auto --skip-git-repo-check)
    else
      args=(exec --full-auto --skip-git-repo-check)
    fi
    if [ -n "${AGENT_MODEL:-}" ]; then args+=(--model "$AGENT_MODEL"); fi
    status=0
    "${strip[@]}" codex "${args[@]}" "${extra[@]}" "$prompt" || status=$?
    write_usage "" "" "${AGENT_CONTEXT_WINDOW:-}"   # not reported; callers use the task cap
    exit "$status"
    ;;

  *)
    echo "unknown AGENT_CLI: $cli" >&2; exit 1 ;;
esac
