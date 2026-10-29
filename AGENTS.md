# Spec-Driven Development on GitHub

Run each epic from a short spec. GitHub's issue graph holds the breakdown, the order, and the state. Separate roles build, check, and merge the work, and every merge rests on evidence, so the same rules hold whether a person is steering or the work runs unattended.

## The Six Principles

### 1. Spec First

**Describe the outcome. Leave out the how.**

A spec records why an epic exists and what done looks like. The method is decided at build time, by whoever implements it. A spec full of steps rots on the first change of plan; a spec that names the outcome survives many implementations.

- Keep it to a page — Why, What, Acceptance criteria, Non-goals
- Write criteria as observable outcomes — each one becomes a check before work starts
- Leave the method to the implementer — the spec says what, not how
- Commit it to the repo — it travels with the code and diffs cleanly

Turn vague intent into checkable criteria:

| Instead of... | Write... |
| --- | --- |
| "Add login" | "A returning user logs in and stays logged in across visits" |
| "Make it secure" | "Passwords are stored hashed, never in plain text" |

**The test:** Could two engineers build from this spec and both satisfy it? If yes, it sits at the right altitude.

### 2. Graph Over Files

**GitHub holds the plan and the state. No second tracker.**

The breakdown is sub-issues under the epic. The order is blocking edges. Progress is open and closed. Nothing duplicates it in a file, so nothing drifts, and a context reset loses no plan because the plan was never in the context.

- Epic — a parent issue, marked with the `epic` label or an `Epic` issue type
- Tasks — sub-issues of the epic, set with `--parent`
- Order — blocking edges set with `--blocked-by`, between tasks or between epics
- Progress — read from the issues, visible to the whole team without translation

**The test:** Can the current state of the work be answered from the issues alone? If a file has to be checked, the graph is not yet carrying it.

### 3. Fence With Non-Goals

**Name what this epic will not do.**

Each line under Non-goals stops a sub-issue from forming and keeps an agent inside scope. It is the cheapest scope control available, and it lives in the spec where the decomposition reads it.

- Say what is out of scope, and where that work lives instead
- Treat deferred scope as future epics, never as quiet additions to this one
- Recheck the fence while pruning the derived sub-issues

**The test:** Does each non-goal prevent a plausible mistake? A fence around nothing is noise.

### 4. Derive, Then Work the Ready Set

**The model breaks down the spec. A person approves it. The graph says what is next.**

Hand-writing every substep over-specifies the how. Let the agent propose atomic sub-issues and their checks; a person prunes and approves both in one review, before anything is created. Work that runs unattended only ever works a graph, and checks, a person has approved.

- Materialize in one pass — parent, blocking edges, and checks set at creation
- Start only ready issues — GitHub serves a blocked issue without complaint
- Give each task its own throwaway plan, made in the session and never written down

**The test:** Did the model write the substeps and a person approve them? If someone hand-wrote the task list, the spec was doing the agent's job.

### 5. Separate the Roles

**Whoever builds a change never approves it.**

An agent that writes both the code and its checks can pass by testing what it built instead of what the spec asked for. Split the work into three roles, each defined by what it sees and what it may change. A role is a boundary, not a persona. A session is a cache, not a role: an implementer may carry what it learned along its chain, but a reviewer always starts fresh, because its independence is the point.

- Orchestrator — owns the graph: derives, materializes, writes the checks, dispatches ready issues, and sets `verdict` from the reviewer's first line, never rewording it. Writes no implementation code; its mechanical parts may run as plain code.
- Implementer — works one sub-issue at a time on its task branch. Sees the spec, the sub-issue, and the code. Never edits the checks. Opens its PR with the report below.
- Reviewer — sees only the spec, the sub-issue, and the diff, never the PR description or the implementer's reasoning. Gives a verdict on scope and non-goals.

**The test:** Did any role approve work it produced? If yes, the roles have collapsed into one.

### 6. Close on Evidence

**An issue closes when a merged PR with passing checks closes it. Never by hand.**

A closed issue is the graph saying the work is done, so the claim needs proof that does not depend on an agent's report. The implementer's PR says `Closes #<n>` and has auto-merge enabled when it opens, so GitHub merges it into the default branch once the `gate` and `verdict` status checks both pass, and the merge closes the issue. No agent decides when to merge.

- Checks come before code — written from the criteria by the orchestrator, as the task branch's `checks: #<n>` commit, never on the default branch
- Checks are fixed during the task — no implementer commit touches a file the checks commit added
- The gate is GitHub's — required status checks, never an agent's say-so
- No manual closes — if the work cannot pass its checks, the issue stays open

**The test:** Can every closed issue point to a merged PR, a passing `gate`, and a passing `verdict`? If one cannot, the graph is reporting a claim, not a fact.

## The Loop

1. A person writes `specs/<number>-<name>.md` from the template below.
2. The orchestrator derives atomic sub-issues and their checks, respecting the non-goals, and asks whatever it needs to; a person approves both.
3. The orchestrator materializes the breakdown in one pass: the issues, their blocking edges, and a `task/<n>` branch per issue whose first commit holds its checks.
4. Each ready issue goes to an implementer, dispatched by the orchestrator or by the loop in `automation/`. Ready issues run in parallel; when a task merges and is the only blocker of the next, the same session continues the chain.
5. The implementer opens a PR with its report; a reviewer gives a verdict.
6. GitHub auto-merges the PR when `gate` and `verdict` pass, and the merge closes the issue. The ready set changes, and the loop repeats.
7. A person closes the epic once its sub-issues are closed.
8. Record non-obvious choices in `DECISIONS/<number>-<name>.md`, such as `DECISIONS/001-use-session-cookies.md`.

## Running the Loop

Before approval, ask freely. While the spec is written and the breakdown derived, clarifying questions are the work: each answer settled then is an issue not parked later.

Approval of the breakdown is the last answer the orchestrator waits for. From then on it runs the loop, and the session stays open for the person. Unattended, the workflows in `automation/` run it the same way, with no chat: real decisions park, and the parked issues are the report.

- Authorized without asking — push `task/<n>` branches, dispatch implementers and reviewers, add and remove `in-progress` and `needs-human`, open PRs, set `verdict`, enable auto-merge
- Minor decision — decide, say so in one line, and continue; list it in the final report
- Real decision — park it with `needs-human`, on the sub-issue or the epic, as in Asking for a Person; never wait on chat for it
- The person may ask or steer at any time — status comes from the graph, and a steer that changes the plan is written to the issue it affects
- Stop when the ready set is empty, then report once: what merged, what is parked and why, and the minor decisions taken

A decision is minor when a person would be fine learning of it afterward.

**The test:** Did the orchestrator ever stop to wait for a chat reply after approval? If yes, a decision escaped the graph.

## Names

Every role and every tool reads the same names, whether a person or a workflow runs the loop.

| Name | Meaning |
| --- | --- |
| `epic` | Label on an epic's parent issue |
| `task/<n>` | Branch for sub-issue `#<n>` |
| chain | A run of tasks, each blocked only by the one before it; ends where the graph branches or joins |
| `checks: #<n>` | Message of the task branch's first commit, which holds its checks |
| `tests/acceptance/` | Checks path, unless the project names another |
| `in-progress` | Issue dispatched; nothing else takes it |
| `needs-human` | Issue parked for a person; it leaves the ready set |
| `gate` | Required status check: the tests and the mechanical guards |
| `verdict` | Required status check the orchestrator, or the review workflow in `automation/`, sets from the reviewer's verdict |
| `Verdict: pass` / `Verdict: fail — <reason>` | First line of the reviewer's verdict, posted on the PR |
| `.github/protected-paths` | Paths whose changes only a person merges |

## Spec Template

```
# <Epic> — Spec
Status: Draft

## Why
The problem, in two to four sentences.

## What
What it does. The outcome, not the method.

## Acceptance criteria
- [ ] Testable, observable outcomes. These become the sub-issue seeds and their checks.

## Non-goals
The fence. Each line stops a sub-issue from forming.
```

## Materialize

Create the epic, then the tasks in dependency order so every reference already exists:

```
gh issue create --title "Epic <number>: <name>" --label epic --body-file specs/<number>-<name>.md
gh issue create --title "<task>" --parent <epic#> --blocked-by <prev#> --body-file .github/tasks/<id>.md
```

Then give each task its branch and checks:

```
git switch -c task/<n> origin/main
# write the checks for #<n> under the checks path
git add <checks path> && git commit -m "checks: #<n>" && git push -u origin task/<n>
```

## Blocking Discipline

- Place each edge where the constraint is real. When one task of epic B depends on epic A, block that single task.
- Skip redundant edges. An edge from epic A to epic B already covers B's children.
- Blocking is advisory. Read an issue's `blockedBy` before starting it.

## Finding Ready Work

An issue is ready when it is open, has no open blocker, has its `task/<n>` branch, and carries neither `in-progress` nor `needs-human`. Nothing is dispatched while the default branch is failing. Whoever dispatches an issue adds `in-progress`; parking it removes it. Read the list of child issues, not the summary counter, which can freeze at the first sub-issue:

```
for n in $(gh issue view <epic#> --json subIssues -q '.subIssues[].number'); do
  blockers=$(gh issue view "$n" --json blockedBy -q '[.blockedBy[] | select(.state=="OPEN")] | length')
  state=$(gh issue view "$n" --json state -q .state)
  held=$(gh issue view "$n" --json labels -q '[.labels[].name] | any(. == "needs-human" or . == "in-progress")')
  git ls-remote --exit-code --heads origin "task/$n" >/dev/null || continue
  [ "$state" = "OPEN" ] && [ "$blockers" -eq 0 ] && [ "$held" = "false" ] && echo "ready -> #$n"
done
```

## Implementer Report

The PR description is the implementer's report. The orchestrator reads it; the reviewer does not. The `gate` already proves the criteria, so the report covers only what the checks cannot:

```
Closes #<n>

### Skipped
- <work left undone, and why>

### Unsure
- <assumptions made, and where a person should look>
```

Empty sections stay, marked `none`.

Open the PR with auto-merge enabled, unless it touches a protected path:

```
gh pr create --base main --head task/<n> --title "<task>" --body-file <report>
gh pr merge task/<n> --auto --squash
```

The orchestrator sets `verdict` on the PR's head commit from the reviewer's first line; unattended, `automation/` opens the PR and sets `verdict` itself:

```
gh api repos/{owner}/{repo}/statuses/<sha> -f context=verdict -f state=success   # or state=failure
```

## Asking for a Person

Once the breakdown is approved, an agent never waits for an answer. It either decides or parks the issue.

- Minor ambiguity — choose the most reasonable reading, record it under Unsure, continue
- Real ambiguity — the spec contradicts itself, the work would cross a non-goal, the choice is a person's to make, or the action cannot be undone. Put the question on the sub-issue, add `needs-human`, and stop work on that issue
- Repeated failure — a failing `gate` or `verdict` gets one more attempt with what failed; a second failure parks the issue

A parked issue leaves the ready set; the rest of the graph keeps moving. A person answers in the comments, then removes `needs-human` to return it with two fresh attempts.

## Guardrails

Agents act with the identity of whoever runs them — a person when steered, the project's GitHub App when unattended — so the limits live here, in the harness, and in the token, not in GitHub approvals.

- Everything through a PR — agents never push to the default branch directly
- Protected paths — a PR whose implementer commits touch a path listed in `.github/protected-paths` gets `needs-human` and no auto-merge, and only a person merges it
- No widening — an agent never adds secrets, raises CI permissions, or edits branch protection
- Nothing outside the repo that cannot be undone — agents do not deploy, publish, or change external systems; those stay with a person. Branches, PRs, labels, comments, and merges through the gate count as inside the repo
