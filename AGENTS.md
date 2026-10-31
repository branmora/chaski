# Spec-Driven Development on GitHub

Run each epic from a short spec. A person shapes and approves the specs up front; from then on the orchestrator runs the work autonomously. GitHub's issue graph holds the breakdown, the order, and the state. Separate roles build, check, and merge the work, and every merge rests on evidence.

## The Six Principles

### 1. Spec First

**Describe the outcome. Leave out the how.**

A spec records why an epic exists and what done looks like. The method is decided at build time, by whoever implements it. A spec full of steps rots on the first change of plan; a spec that names the outcome survives many implementations.

- Keep it to a page — Why, What, Acceptance criteria, Non-goals
- Write criteria as observable outcomes — each one becomes a check before work starts
- Leave the method to the implementer — the spec says what, not how
- Commit it to the repo — it travels with the code and diffs cleanly
- Approving the spec is the person's main act — mark it `Status: Approved`

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
- Progress — read from the issues, visible to the whole team without translation; a spec is never edited to record progress

**The test:** Can the current state of the work be answered from the issues alone? If a file has to be checked, the graph is not yet carrying it.

### 3. Fence With Non-Goals

**Name what this epic will not do.**

Each line under Non-goals stops a sub-issue from forming and keeps an agent inside scope. It is the cheapest scope control available, and it lives in the spec where the decomposition reads it.

- Say what is out of scope, and where that work lives instead
- Treat deferred scope as future epics, never as quiet additions to this one
- Recheck the fence while deriving the sub-issues

**The test:** Does each non-goal prevent a plausible mistake? A fence around nothing is noise.

### 4. Derive, Then Work the Ready Set

**A person approves the spec. The orchestrator breaks it down. The graph says what is next.**

Hand-writing every substep over-specifies the how. The person's judgment goes into the spec, where it is cheapest; the orchestrator derives atomic sub-issues and their checks from it and materializes them without waiting. The person can read and steer the graph at any time, but nothing waits on them.

- Materialize in one pass — parent, blocking edges, and checks set at creation
- Derive an epic when it becomes ready, so its breakdown sees the code its blockers left
- Start only ready issues — GitHub serves a blocked issue without complaint
- Give each task its own throwaway plan, made in the session and never written down

**The test:** Did the model write the substeps from a spec a person approved? If someone hand-wrote the task list, the spec was doing the agent's job.

### 5. Separate the Roles

**Whoever builds a change never approves it.**

An agent that writes both the code and its checks can pass by testing what it built instead of what the spec asked for. Split the work into three roles, each defined by what it sees and what it may change. A role is a boundary, not a persona. A session is a cache, not a role: an implementer may carry what it learned along its chain, but a reviewer always starts fresh, because its independence is the point. A cache only pays while it is warm, so no role idles to keep one alive.

- Orchestrator — the brain of the run: derives, materializes, writes the checks, dispatches ready issues, decides what the spec leaves open, merges on evidence, and closes finished epics. Writes no implementation code; its mechanical parts may run as plain code.
- Implementer — works one sub-issue at a time on its task branch. Sees the spec, the sub-issue, and the code. Never edits the checks. Opens its PR with the report below.
- Reviewer — sees only the spec, the sub-issue, and the diff, never the PR description or the implementer's reasoning. Gives a verdict on scope and non-goals.

**The test:** Did any role approve work it produced? If yes, the roles have collapsed into one.

### 6. Close on Evidence

**An issue closes when a merged PR with passing checks closes it. Never by hand.**

A closed issue is the graph saying the work is done, so the claim needs proof that does not depend on an agent's report. The implementer's PR says `Closes #<n>`. The orchestrator merges it as in Merging, and the merge closes the issue.

- Checks come before code — written from the criteria by the orchestrator, as the task branch's `checks: #<n>` commit, never on the default branch
- Checks are fixed for the implementer — no implementer commit touches a file a checks commit added
- The gate is GitHub's — a status check from CI, never an agent's say-so
- No manual closes — a task closes only through its merged PR; an epic closes when its last sub-issue does, with no PR of its own

**The test:** Can every closed issue point to a merged PR, a passing `gate`, and a `Verdict: pass`? If one cannot, the graph is reporting a claim, not a fact.

## The Loop

1. A person brainstorms with the orchestrator. The outcome is a set of specs, one per epic, each `specs/<number>-<name>.md` from the template below, and the order between them.
2. The person approves the set at once, marking each spec `Status: Approved`. This is the last answer the orchestrator waits for; from here it runs autonomously. An idea not ready yet stays a spec marked `Status: Draft`, which the orchestrator never runs.
3. The orchestrator creates an epic issue per approved spec, with blocking edges between epics.
4. When an epic is ready, the orchestrator derives its sub-issues and checks, respecting the non-goals, and materializes them in one pass: the issues, their blocking edges, and a `task/<n>` branch per issue whose first commit holds its checks.
5. Each ready issue goes to an implementer. Ready issues run in parallel; when a task merges and is the only blocker of the next, the same session continues the chain.
6. The implementer opens a PR with its report; a reviewer gives a verdict.
7. The orchestrator merges the PR, and the merge closes the issue. When an epic's last sub-issue closes, the orchestrator closes the epic issue and continues with the next, no PR and no permission needed. The ready set changes, and the loop repeats.
8. Record non-obvious choices in `DECISIONS/<number>-<name>.md`, such as `DECISIONS/001-use-session-cookies.md`.

## Running the Loop

**Brainstorming** — ask freely. While the specs are written, clarifying questions are the work: each answer settled then is an issue not parked later.

**Autonomous run** — after approval, the orchestrator works through every approved epic without waiting, and the session stays open for the person.

Authorized without asking: derive and materialize epics, push `task/<n>` branches, dispatch implementers and reviewers, add and remove `in-progress`, open and merge PRs that pass, add, split, or reorder sub-issues inside the spec's fence, rewrite checks that misread the spec, close finished epics.

The orchestrator makes each decision itself or parks it, as in When to Ask a Person, and notes it in one line on the issue it affects; it never waits on chat, because a question in chat stalls the run while the graph keeps it moving. The person may ask or steer at any time. Status comes from the graph, and a steer that changes the plan is written to the issue it affects, so the plan stays in one place.

A role that starts a process likely to outlast its session's cache detaches it with its output in a log, posts `Waiting: <command> → <log>` on the sub-issue, and ends its turn. The orchestrator watches for the exit line, never the log's contents, and resumes that role once; a nonzero exit counts as a failed attempt.

It posts one line in the chat when an epic closes or an issue is parked, so the person hears about anything that waits on them. When the ready set is empty across all approved epics, it stops and reports what merged, which epics closed, what is parked and why, and the decisions taken.

**The test:** Did the orchestrator ever stop to wait for a chat reply after approval, or park something a person would have been fine learning of afterward? If yes, a decision escaped the orchestrator.

## Names

Every role and every tool reads the same names.

| Name | Meaning |
| --- | --- |
| `epic` | Label on an epic's parent issue |
| `Status: Approved` | Line in a spec that lets the orchestrator run it; `Status: Draft` holds it back |
| `task/<n>` | Branch for sub-issue `#<n>` |
| chain | A run of tasks, each blocked only by the one before it; ends where the graph branches or joins |
| `checks: #<n>` | Message of a commit holding checks: the task branch's first commit, or a later rewrite by the orchestrator |
| `tests/acceptance/` | Checks path, unless the project names another |
| `in-progress` | Issue dispatched; nothing else takes it |
| `needs-human` | Issue parked for a person on a critical decision; it leaves the ready set |
| `Waiting: <command> → <log>` | Comment on a sub-issue whose role is waiting on detached work; the issue keeps `in-progress` |
| `gate` | Status check from CI: the tests and the mechanical guards |
| `Verdict: pass` / `Verdict: fail — <reason>` | First line of the reviewer's verdict, posted on the PR |

## Spec Template

```
# <Epic> — Spec
Status: Draft

## Why
The problem, in two to four sentences.

## What
What it does. The outcome, not the method.

## Acceptance criteria
- Testable, observable outcomes. These become the sub-issue seeds and their checks.

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

An issue is ready when it is open, has no open blocker, has its `task/<n>` branch, and carries neither `in-progress` nor `needs-human`. An epic is ready to derive when it is open, has no open blocker, and has no sub-issues yet. Nothing is dispatched while the default branch is failing. Whoever dispatches an issue adds `in-progress`; parking it removes it. Read the list of child issues, not the summary counter:

```
for n in $(gh issue view <epic#> --json subIssues -q '.subIssues[].number'); do
  blockers=$(gh issue view "$n" --json blockedBy -q '[.blockedBy[] | select(.state=="OPEN")] | length')
  state=$(gh issue view "$n" --json state -q .state)
  held=$(gh issue view "$n" --json labels -q '[.labels[].name] | any(. == "needs-human" or . == "in-progress")')
  git ls-remote --exit-code --heads origin "task/$n" >/dev/null || continue
  [ "$state" = "OPEN" ] && [ "$blockers" -eq 0 ] && [ "$held" = "false" ] && echo "ready -> #$n"
done
```

`in-progress` holds only while the session that set it is alive. A new orchestrator session first reads the issues that carry `in-progress`. One whose last comment is `Waiting:` gets its watch back, or is resumed if the log already ends. Any other returns to the ready set: remove `in-progress`; the task branch keeps whatever was pushed.

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

```
gh pr create --base main --head task/<n> --title "<task>" --body-file <report>
```

## Merging

The orchestrator merges a PR into the default branch when its `gate` passes and the reviewer's verdict reads `Verdict: pass`. The merge is mechanical: a PR that passes both is merged, and one that does not is not. Skipped or Unsure work the spec still needs becomes a new sub-issue.

```
gh pr checks task/<n> && gh pr merge task/<n> --squash --delete-branch
```

## When to Ask a Person

Once the specs are approved, the orchestrator is the one who decides. Implementers never park an issue: a minor ambiguity is resolved by the most reasonable reading and recorded under Unsure; anything larger goes back to the orchestrator as a comment on the sub-issue.

The orchestrator parks with `needs-human` only when the decision is critical:

- The action cannot be undone, or reaches outside the repo — deploy, publish, external systems, secrets, permissions
- The work cannot be done without crossing a non-goal or changing what the approved spec means
- The issue has run out of moves — see below

Everything else, the orchestrator decides: open questions the spec leaves, task order, splitting or adding sub-issues inside the fence, the reading of an unclear criterion.

Failures follow one path. A failing `gate` or verdict goes back to the implementer with what failed. On a second failure, the orchestrator makes one move: retry with a fresh implementer, split the task, or rewrite checks that misread the spec. If the issue fails again, it parks.

To park, put the question on the issue, add `needs-human`, and remove `in-progress`. A parked issue leaves the ready set; the rest of the graph keeps moving. A person answers in the comments, then removes `needs-human` to return it with fresh attempts.

## Guardrails

Agents act with the identity of the person who runs them, so the limits live here, in the harness, and in the token.

- Everything through a PR — agents never push to the default branch directly
- No widening — an agent never adds secrets, raises CI permissions, or edits branch protection
- Nothing outside the repo that cannot be undone — agents do not deploy, publish, or change external systems; those stay with a person. Branches, PRs, labels, comments, merges on evidence, and closing epics count as inside the repo
