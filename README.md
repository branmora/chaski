# Spec-Driven Development on GitHub

A single convention for running spec-driven development on GitHub's native issue features. Work runs in two phases. In **brainstorming**, a person and the orchestrator write one short spec per epic, and the person approves the set. In the **autonomous run**, the orchestrator does the rest: the issue graph carries the breakdown, the order, and the state, separate roles build and check the work, and every merge rests on evidence.

## The Problem

Spec-driven development tools keep growing a project-management layer of their own. Specs, task lists, status, and dependencies all land in files: a `specs/` tree, a state JSON, steering documents. That layer made sense when GitHub issues were flat and could not express hierarchy or dependencies.

Three problems follow from carrying it:

- **A second source of truth.** Status lives in files and also in the issue tracker, and the two drift. The code says one thing, the state file another, the open issues a third.
- **No home for dependencies.** Each spec sits alone in its folder. The everyday statement "this epic needs that one first" has nowhere native to live, so the order survives in a teammate's memory.
- **State that dies on reset.** A plan held in chat or scratch files vanishes when the context resets, and the agent rebuilds it from scratch, often differently.

A fourth problem appears once agents do most of the work:

- **Agents grading their own work.** The agent that writes the code also writes the tests and reports that everything passes. Its report is the only evidence, and models describe their own work generously.

## The Solution

GitHub issues now express hierarchy and dependencies directly, all scriptable through `gh`: sub-issues, blocking relationships, and issue types. The project-management layer already exists, in the place the team already looks. Branches, pull requests, labels, and status checks already exist too, and they are enough to keep builders and judges apart. Six principles put it to work.

| Principle | Addresses |
| --- | --- |
| **Spec First** | Scattered intent, specs that drift from the code |
| **Graph Over Files** | A second source of truth, state lost on reset |
| **Fence With Non-Goals** | Scope creep, bloated epics |
| **Derive, Then Work the Ready Set** | Hand-written task lists, unclear order |
| **Separate the Roles** | Agents grading their own work |
| **Close on Evidence** | A graph that reports claims instead of facts |

## What It Looks Like

Take a feature: user accounts. Start with a one-page spec, `specs/001-user-authentication.md`:

```
# User Authentication — Spec
Status: Approved

## Why
Today everything is anonymous and lost on refresh. Users need accounts to save work.

## What
Email-and-password signup, login, logout, and a session that persists across visits.

## Acceptance criteria
- A visitor creates an account with email and password
- A returning user logs in and stays logged in across visits
- A logged-in user can log out
- Passwords are stored hashed, never in plain text

## Non-goals
- No social login in v1
- No password reset flow yet
- No two-factor auth
```

It comes out of a brainstorm with the orchestrator, usually alongside the other specs of the project. Once the questions run out, the person approves the whole set at once by marking each spec `Status: Approved`. That is the last answer the orchestrator waits for, and the autonomous run begins. It breaks the spec into atomic sub-issues, respecting the non-goals, and materializes them to GitHub in one pass. The epic is created first, then each task with its parent, its blocker, and its body set at creation:

```
gh issue create --title "Epic 001: User authentication" --label epic --body-file specs/001-user-authentication.md              # -> #1
gh issue create --title "User schema and password hashing" --parent 1                --body "Passwords are stored hashed"      # -> #2
gh issue create --title "Signup endpoint and form"         --parent 1 --blocked-by 2 --body "A visitor creates an account"     # -> #3
gh issue create --title "Login and session persistence"    --parent 1 --blocked-by 2 --body "A returning user stays logged in" # -> #4
gh issue create --title "Logout"                           --parent 1 --blocked-by 4 --body "A logged-in user can log out"     # -> #5
```

GitHub now holds the whole plan. The epic shows its children and their order:

```
#1  Epic 001: User authentication          [epic]
├─ #2  User schema and password hashing    ready
├─ #3  Signup endpoint and form            blocked by #2
├─ #4  Login and session persistence       blocked by #2
└─ #5  Logout                              blocked by #4
```

Before any code exists, the orchestrator turns each task's criteria into checks, committed as the first commit on its branch: `task/2` starts with `checks: #2`. They are the contract, and no implementer may change them.

Only `#2` has no open blocker, so it is the single task ready to start. An implementer works it on `task/2` and opens a PR that says `Closes #2`. GitHub runs the `gate` check, a reviewer that sees only the spec, the task, and the diff posts its verdict, and when both pass the orchestrator merges the PR and `#2` closes. `#3` and `#4` open up and can run in parallel. Merge `#4`, and `#5` follows. When the last of them closes, the orchestrator closes the epic and moves to the next approved one. The spec stays in the repo as the record of intent. The issue graph runs the work, and every closed issue points to a merged PR, a passing `gate`, and a `Verdict: pass`.

That is the whole method. The principles below explain why each move is shaped the way it is.

## The Six Principles in Detail

### 1. Spec First

**Describe the outcome. Leave out the how.**

A spec records why an epic exists and what done looks like, and it stays out of the method. Agents reach for implementation detail early and bake decisions into a document meant to outlive them. A spec that records the outcome survives many implementations. A spec stuffed with steps rots on the first change of plan.

- Keep it to a page — Why, What, Acceptance criteria, Non-goals
- Write criteria as observable outcomes — each one becomes a check before work starts
- Leave the method to the implementer — the spec says what, not how
- Commit it to the repo — it travels with the code and diffs cleanly

**The test:** Could two engineers build from this spec and both satisfy it? If yes, it sits at the right altitude.

### 2. Graph Over Files

**GitHub's issue graph is the plan and the state.**

The breakdown lives as sub-issues under the epic. The order lives as blocking edges. Progress lives in open and closed. Nothing duplicates it in a file, so nothing drifts, and a context reset loses no plan because the plan was never in the context.

- Epic — a parent issue, marked with an `epic` label or an `Epic` issue type
- Tasks — sub-issues of the epic
- Order — blocking edges, between tasks and between epics alike
- Progress — read straight from the issues, visible to the whole team; the spec is never edited to record it

**The test:** Can the state of the work be answered from the issues alone? If a file has to be checked, the graph is not yet carrying it.

### 3. Fence With Non-Goals

**The non-goals section does real work.**

Every line under Non-goals stops a sub-issue from forming and keeps an agent inside the scope of the epic. In the example, "no password reset yet" is the only reason a reset task did not appear in the breakdown. The reviewer reads the same fence, so it holds through review as well as derivation.

- Name what the epic will not do, and where that work lives instead
- Treat deferred scope as future epics, never as quiet additions to this one
- Recheck the fence while deriving the sub-issues

**The test:** Does each non-goal prevent a plausible mistake? A fence around nothing is noise.

### 4. Derive, Then Work the Ready Set

**A person approves the spec. The orchestrator decomposes it. Work flows in unblocked order.**

Hand-writing every substep wastes effort and over-specifies the how. The person's judgment goes into the spec, where it is cheapest. The orchestrator derives atomic sub-issues and their checks from it, materializes them without waiting, and the dependency graph decides what is ready. Each task carries its own throwaway plan, made fresh in the session and never written down. The person can read and steer the graph at any time, but nothing waits on them.

- Derive an epic when it becomes ready, so its breakdown sees the code its blockers left
- Materialize in one pass, with parent, blocking edges, and checks set at creation
- Start only issues with no open blockers
- Record non-obvious choices as numbered files in `DECISIONS/`, such as `DECISIONS/001-use-session-cookies.md`, when a spec shifts mid-flight

**The test:** Did the model write the substeps from a spec a person approved? If someone hand-wrote the task list, the spec was doing the agent's job.

### 5. Separate the Roles

**Whoever builds a change never approves it.**

An agent that writes both the code and its tests can pass by testing what it built instead of what the spec asked for. Three roles keep building and judging apart, each defined by what it sees and what it may change, not by a persona.

- Orchestrator — the brain of the run: derives, materializes, writes the checks, dispatches ready work, decides what the spec leaves open, merges on evidence, closes finished epics. Writes no implementation code. Its mechanical half can be plain code.
- Implementer — one sub-issue, one branch. Cannot change the checks it must pass. Reports only what the checks cannot show: what it skipped and what it is unsure of.
- Reviewer — sees only the spec, the sub-issue, and the diff, never the implementer's reasoning, so it is not anchored to the choices it judges. Rules on scope and non-goals; correctness is the gate's job.

**The test:** Did any role approve work it produced? If yes, the roles have collapsed into one.

### 6. Close on Evidence

**An issue closes when a merged PR with passing checks closes it. Never by hand.**

A closed issue is the graph saying the work is done, so the claim needs proof that does not rest on an agent's report. The checks are written from the criteria before the code, and GitHub, not an agent, records whether they pass. `gate` is a CI status check that runs the tests; the reviewer's verdict is a comment on the PR. The orchestrator merges when the checks are untouched, `gate` passes, and the verdict reads `Verdict: pass`, and `Closes #<n>` closes the issue. The merge is mechanical: the orchestrator never merges on its own judgment and never holds back a PR that passed.

- Checks come before code, written by the orchestrator from the approved criteria
- Checks are fixed during the task; the orchestrator refuses to merge a branch whose implementer commits touched one
- The gate is GitHub's status checks, never an agent's say-so
- No manual closes; work that cannot pass stays open, and an epic closes when its last sub-issue does

**The test:** Can every closed issue point to a merged PR, a passing `gate`, and a `Verdict: pass`? If one cannot, the graph is reporting a claim, not a fact.

## Running Unattended

The same rules run without you. [`automation/`](automation/) holds GitHub Actions templates that work the ready set overnight: a merge to the default branch starts the next dispatch, each ready issue starts an implementer session, and every PR gets the gate and a reviewer. A session that finishes a task continues to the next one in its chain, so sequential work does not pay to relearn the repository; parallel sessions start only where the graph branches. Agents act as the project's GitHub App, never hold GitHub credentials themselves, and park anything ambiguous with `needs-human`. You come back to closed issues with evidence attached and a short list of questions.

Two of the three workflows run whether you steer or not: the gate and the reviewer are what produce `gate` and `verdict` on every task PR. Only the dispatch loop is optional, switched on with one repository variable.

## Why Lite

A lighter convention earns its place three ways. It removes a moving part, since no state file means nothing to sync and nothing to drift. It puts the work where people already look, so status is visible to teammates and other tools with no translation step. And it shrinks what an agent must learn: read the spec for the goal, query the graph for what is ready, write a throwaway plan for each task.

It is also cheap to run, by construction rather than by instruction. The cost that matters is cost per closed issue, and most of it is an agent learning the repository. Sessions are reused along chains of sequential work and started fresh only where the graph allows parallel work or a role needs independence.

The roles and the gate add no tracker of their own. They use branches, pull requests, labels, and status checks GitHub already has, and they state authority and evidence rather than method, so they hold as models improve.

Heavier frameworks add phases, validators, and harnesses, and those pay off at large scale. For a solo developer or a small team, a spec plus the issue graph covers the same ground with far less to carry.

## Install

Copy the shared agent instructions into a project:

```
curl -o AGENTS.md https://raw.githubusercontent.com/branmora/spec-driven-github/main/AGENTS.md
```

If the project already has an `AGENTS.md`, add the convention there instead of replacing its existing instructions.

[Claude Code 2.1.277 and later](https://code.claude.com/docs/en/changelog) can read `AGENTS.md` by default when the project has no `CLAUDE.md` or `CLAUDE.local.md`. If the project has either file, or a Claude Code session [cannot load `AGENTS.md` directly](https://code.claude.com/docs/en/memory#when-agentsmd-support-is-unavailable), add this import to `CLAUDE.md`:

```
@AGENTS.md
```

To run it unattended, follow [`automation/README.md`](automation/README.md).

## Requirements

A current `gh` with native `--parent` and `--blocked-by` support.

A CI check named `gate` that runs the project's tests on pull requests and on the default branch. If the project already has CI, name its test job `gate`. If it has none, this workflow is enough, with the test command swapped for the project's own:

```yaml
# .github/workflows/gate.yml
name: gate
on:
  pull_request:
  push:
    branches: [main]
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: npm test
```

Issue types need a GitHub organization. Without one, epics use a label, and everything else works the same.
