# 001 — Model and effort per role

Status: Accepted · 2026-10-29
Snapshot: branched from `main` at `febc7d8`; reviewed against the autonomous run (#5), only the orchestrator's reasons changed. This choice dates as models ship.

## Decision

| Role | Model | Effort | Cache TTL |
|---|---|---|---|
| Orchestrator | Opus 5.5 | `xhigh` | 1h (default) |
| Ready set and dispatch | none (the loop in AGENTS.md, Finding Ready Work) | — | — |
| Implementer | Opus 5.5 | `medium` | 1h, set in its frontmatter |
| Reviewer | Opus 5.5 | `high` | 5m (default) |
| Explore | Haiku 5.5 | `medium` | 5m (default) |

The orchestrator is the main session, so its model and effort are set in the session. Subagents take theirs from the `model`, `effort`, and `experimental.cacheTtl` fields of their agent file.

1h holds only while the subscription is within plan usage. On usage credits, Claude Code ignores the implementer's 1h and the main session drops to 5m, both without notice.

## Why

- Opus for every role that writes or judges, for reliability on code and facts.
- An implementer's chain stays on one model, because a cache does not carry across models. The reviewer starts fresh, so for it the reason is quality, not cache.
- Effort is set per role and never changed mid-session. With dispatch scripted, the orchestrator's remaining turns need judgment, not speed: it makes the run's decisions, derives epics without review, and handles repeated failures.
- The implementer needs 1h because subagents default to 5m. A chain waits on `gate` and the reviewer's verdict between tasks, and detached work resumes the implementer once it finishes; any resume within the hour reads a warm cache.
- 1h costs 2x base input on every cache write instead of 1.25x. It pays off when waits before a resume fall between 5 and 60 minutes, and is wasted on shorter waits, on waits over an hour, and on implementers never resumed.
- Explore is search, not judgment, so Haiku.

## Do not

- Set a subagent TTL globally: the `subagentPromptCacheTtl` setting or the `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL` variable. Either overrides every subagent's frontmatter, including the reviewer's and Explore's.
- Set `ENABLE_PROMPT_CACHING_1H=1`. It requests 1h for every subagent, not just the implementer.
- Set `FORCE_PROMPT_CACHING_5M=1`. It overrides everything and silently drops the implementer to 5m.

## Not chosen

- Sonnet for isolated tasks: cheaper, but weaker on code and facts; one retry erases the saving.
- A different model for the reviewer: less correlated blind spots, but weaker judgment on scope.
- Raising effort on retry: not documented for resumed subagents.
- Lowering orchestrator effort after approval: approval comes before nearly the whole run, so it would lower effort where the judgment is.
- Separate implementer files by TTL: whether 1h pays off depends on how long each wait before a resume lasts, which is rarely known when the implementer starts.

## Revisit when

A new model generation ships, `experimental.cacheTtl` changes in Claude Code, or after a few epics, subagent transcripts show 1h writes (`ephemeral_1h_input_tokens`) without matching resumes within the hour.
