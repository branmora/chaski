# Running the convention unattended

Templates that run the loop in [AGENTS.md](../AGENTS.md) with GitHub Actions, so work continues while nobody is steering. GitHub is the scheduler, the state store, and the audit log; these files are the glue between its events.

## How it runs

```
merge to main ──► sdd-gate on main ──green──► sdd-dispatch
                                               │  picks ready issues, adds in-progress
                                               ▼
                              one implementer session per issue, in parallel
                              ┌──────────────────────────────────────────────┐
                              │ work task/<n> ─► push, PR, auto-merge         │
                              │      ▲             │                          │
                              │      │       sdd-gate ──► `gate`              │
                              │ retry once   sdd-review ─► `verdict`          │
                              │ (same session)     │                          │
                              │      └── fail ─────┤                          │
                              │                 merged                        │
                              │                    │                          │
                              │   next in chain? ──┴─► continue, same session │
                              └──────────────────────────────────────────────┘
                                  second failure, question, or protected path
                                  ──► needs-human
```

| File | Role |
| --- | --- |
| `workflows/sdd-dispatch.yml` | Computes the ready set, locks issues with `in-progress`, starts one implementer session per issue |
| `workflows/sdd-gate.yml` | The `gate` check: your tests, plus the guards that the checks are unchanged and protected paths go to a person |
| `workflows/sdd-review.yml` | The reviewer, and the `verdict` check |
| `sdd/chain.sh` | One implementer session working a chain of tasks: works, publishes, waits for evidence, retries, continues |
| `sdd/run-agent.sh` | The only file that knows which agent CLI runs; switch from Claude Code to Codex here |
| `sdd/dispatch.sh`, `review.sh`, `gate-checks.sh`, `lib.sh` | Dispatch, reviewer plumbing, gate guards, shared helpers |
| `sdd/prompts/*.md` | Thin role prompts; the rules live in AGENTS.md |

Nothing here derives epics or writes checks. That stays with an orchestrator session, working from specs a person approved: the loop only works issues whose `task/<n>` branch and checks already exist.

## Chains: why sessions are reused

Most of what an agent spends on a task is learning the repository. In a chain, a run of tasks each blocked only by the one before it, the next task needs almost everything the last one learned. So a session that finishes a task keeps going: once its PR merges and `main` is green, it claims the next task in the chain and resumes with that task's context added.

The rules do not bend for this. Every task still merges on its own `gate` and `verdict` before the next one starts, because the next one is not ready until then. Only the session is reused. Parallel sessions start where the graph branches or joins, and the reviewer always starts fresh: a session is a cache, not a role.

A session stops chaining when the next step would cost more than a fresh start or risk the run:

| Stop when | Variable | Default |
| --- | --- | --- |
| The session's context passes this share of the window | `CHAIN_MAX_CONTEXT` | `0.6` |
| It has done this many tasks | `CHAIN_MAX_TASKS` | `5` |
| Less than this much job time is left | `CHAIN_TASK_RESERVE_MINUTES` | `60` |
| The dispatch window has closed | `LOOP_WINDOW` | unset |

The context reading comes from what the CLI reports, never from a number in the convention, so a larger window or better compaction changes one variable. When a CLI does not report context, the task cap decides.

A failed attempt is retried in the same session, so the agent knows exactly what it tried. Each PR's report ends with a run line the script writes, not the agent: the session, the task's cost, and the session's context. That is how you measure cost per closed issue, and whether chaining pays.

## What keeps it contained

- **Agents hold no credentials.** The agent runs with the GitHub token and the App's key stripped from its environment. Scripts push, open the PR, and post comments after it exits. The reviewer runs in a job with no checkout and no token at all, on a folder holding only the spec, the sub-issue, and the diff.
- **The guards come from the default branch.** The gate and reviewer run their scripts and read `.github/protected-paths` from `main`, never from the PR they judge. The implementer job runs the default branch's scripts from outside the working tree.
- **The token cannot widen itself.** The GitHub App has no Workflows or Administration permission, so nothing it pushes can change a workflow file or branch protection; GitHub rejects the push.
- **GitHub merges, not an agent.** Auto-merge fires only when the required `gate` and `verdict` checks pass.
- **Runners are disposable.** Each job runs on a fresh GitHub-hosted VM that is thrown away after.
- **Repository config cannot steer the agent.** With an API key, Claude Code runs in bare mode, which skips hooks, MCP servers, and settings a branch could carry.
- **Budgets are bounded.** A job timeout, a turn limit and optional spend cap per agent run, two attempts per task, the chain limits above, and a cap on parallel sessions.

One honest limit: stripping credentials removes the accidental path, but the implementer still shares a machine with the script that holds them. A chain runs for hours, longer than an App token lives, so the implementer job holds the App's private key to mint fresh tokens. Against a deliberately adversarial agent, run the implementer in a container without them, as described under Stricter setup.

## Setup

### 1. Copy the files

From the root of your project, with this repository checked out next to it:

```
mkdir -p .github/workflows
cp ../chaski/automation/workflows/*.yml .github/workflows/
cp -r ../chaski/automation/sdd .github/sdd
cp ../chaski/.github/protected-paths .github/protected-paths   # if not already there
chmod +x .github/sdd/*.sh
```

The workflows name the default branch `main`. If yours differs, replace `main` in the three workflow files and set the `DEFAULT_BRANCH` variable.

### 2. Create the GitHub App

Settings → Developer settings → GitHub Apps → New GitHub App. No webhook. Repository permissions:

| Permission | Access | Used for |
| --- | --- | --- |
| Contents | Read and write | Pushing task branches |
| Issues | Read and write | Labels, comments, parking |
| Pull requests | Read and write | Opening PRs, auto-merge, verdict comments |
| Commit statuses | Read and write | The `verdict` check |
| Actions | Read | Reading gate results and failure logs |
| Metadata | Read | Required |

Leave **Workflows** and **Administration** at No access. Install the App on the repository, note its App ID, and generate a private key.

The App is the agents' identity. Commits and PRs from the loop show as the App, separate from your own work, which is what makes the history auditable.

### 3. Secrets and variables

Settings → Secrets and variables → Actions.

Secrets:

| Secret | Value |
| --- | --- |
| `SDD_APP_PRIVATE_KEY` | The App's private key |
| `ANTHROPIC_API_KEY` | For Claude Code. Recommended: it runs the agent in bare mode |
| `CLAUDE_CODE_OAUTH_TOKEN` | Alternative for Claude Code, from `claude setup-token`; runs without bare mode |
| `OPENAI_API_KEY` | For Codex, if you use it |

Variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `SDD_APP_ID` | — | The App ID |
| `TEST_COMMAND` | — | Your full test command, including the checks path |
| `LOOP_ENABLED` | `false` | `true` turns dispatch on. The gate and reviewer run either way |
| `LOOP_WINDOW` | unset | Hours dispatch may start and chains may continue, such as `22-07`; unset means any time |
| `LOOP_TZ` | `UTC` | Time zone for the window, such as `America/New_York` |
| `LOOP_MAX_PARALLEL` | `2` | Implementer sessions at once |
| `CHAIN_MAX_CONTEXT` | `0.6` | Share of the context window at which a session stops chaining |
| `CHAIN_MAX_TASKS` | `5` | Tasks per session |
| `CHAIN_TIMEOUT_MINUTES` | `300` | Job timeout for a session (GitHub allows up to 360) |
| `CHAIN_TASK_RESERVE_MINUTES` | `60` | Job time a session keeps in hand before taking another task |
| `WAIT_MINUTES` | `45` | How long a session waits for a PR's checks and merge |
| `AGENT_CLI` | `claude` | `claude` or `codex` |
| `AGENT_MODEL` | CLI default | Model for agent runs |
| `AGENT_CONTEXT_WINDOW` | reported by CLI | Window size, when the CLI does not report one |
| `AGENT_MAX_TURNS` | `80` | Turn limit per agent run (reviewer: `40`) |
| `AGENT_MAX_BUDGET_USD` | unset | Spend cap per Claude Code run |
| `AGENT_TIMEOUT_MINUTES` | `30` | Job timeout for the reviewer |
| `MERGE_METHOD` | `squash` | `squash`, `merge`, or `rebase` |
| `AGENT_ARGS` | unset | Extra CLI flags, appended as-is |

### 4. Labels

```
gh label create epic        --color 5319e7 --description "Parent issue of an epic"
gh label create in-progress --color fbca04 --description "Dispatched; nothing else takes it"
gh label create needs-human --color d93f0b --description "Parked for a person"
```

### 5. Branch protection on `main`

Settings → Rules → New branch ruleset, targeting the default branch:

- Require a pull request before merging, with zero required approvals (agents and you share no approval flow)
- Require status checks to pass: `gate` and `verdict`. Each appears in the picker once it has run, so open one task PR first
- Block force pushes

Then Settings → General → allow auto-merge.

### 6. Turn it on

Approve specs and let an orchestrator session materialize their epics, as AGENTS.md describes. Set `LOOP_ENABLED` to `true`, and optionally `LOOP_WINDOW`. Start a first run from the Actions tab with **sdd-dispatch → Run workflow**, or wait for the next merge or the hourly backstop.

## Working alongside it

The loop and your own sessions share one graph and one lock. Add `in-progress` to an issue you are working by hand and the loop leaves it alone. Your own task PRs go through the same gate and reviewer, so they need the same `gate` and `verdict` to merge; if one fails, it is yours to fix.

In the morning the graph is the report: what closed, each with a merged PR, two passing checks, and a run line, and what is parked:

```
gh issue list --label needs-human
```

Answer each parked issue in its comments, then remove `needs-human` to return it with two fresh attempts. Removing the label starts a dispatch.

The workflows never close epics. The next orchestrator session closes those whose sub-issues are all closed, or you close them yourself.

## Stricter setup

For when nobody will catch a mistake for a while, or the repository matters more:

- **Container isolation.** Run the implementer in a container with no access to the job's environment, passing in only the working tree and the model key, so the token and the App key are unreachable even to a determined agent.
- **Restricted egress.** Limit the runner's outbound network to the package registries, GitHub, and the model API. The October 2026 lab incidents with agents reaching live websites are the reason to treat this as the next step, not a luxury.
- **CODEOWNERS with required review.** Because the agents have their own identity, a person can now approve their PRs. List the sensitive paths in `CODEOWNERS`, require code-owner review, and protected paths are enforced by GitHub instead of by labels.
- **A mechanical criteria check.** Have the gate confirm every check listed in the sub-issue exists under the checks path and ran.

## Troubleshooting

- **The loop stops after one PR.** Something ran with the default `GITHUB_TOKEN`, whose actions start no other workflows. Every write here uses the App token; check that `SDD_APP_ID` and `SDD_APP_PRIVATE_KEY` are set.
- **Nothing dispatches.** Check `LOOP_ENABLED`, `LOOP_WINDOW`, whether the latest gate run on `main` is green, and whether `in-progress` is still on open issues nobody is working.
- **An issue is parked for a missing branch.** The loop only works issues whose `task/<n>` branch starts with a `checks: #<n>` commit.
- **Chains never continue.** Read the session's log in the implement job: it says which limit ended the chain. A run line with no context figure means the CLI did not report one, so only the task cap applies.
- **CLI flags changed.** `sdd/run-agent.sh` follows each CLI's documented headless mode. When you upgrade the CLI, check its flags there; nothing else depends on them. Codex session resume and usage reporting are the least verified parts.
