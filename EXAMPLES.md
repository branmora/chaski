# Example: one epic, end to end

This is the full version of the user-authentication epic from the README, with the task bodies, the checks, and the working queries. The shape is the same for any epic: a person writes and approves the spec; the orchestrator derives the breakdown, materializes it with its checks, and works the ready set.

## 1. The spec

`specs/001-user-authentication.md`:

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

## 2. Derive

Once the spec reads `Status: Approved`, the orchestrator breaks it into atomic sub-issues, respecting the non-goals, without asking again.

Four tasks come out. The schema and hashing come first because signup and login both depend on it; logout depends on a session existing, so it follows login. Notice what the fence kept out: no reset task, no social-login task. The person's say went into the spec; the breakdown follows from it.

## 3. Materialize

Create the epic, then the tasks in dependency order so every reference already exists. No organization here, so the epic uses a label:

```
gh issue create --title "Epic 001: User authentication" --label epic --body-file specs/001-user-authentication.md   # -> #1
gh issue create --title "User schema and password hashing"  --parent 1               --body-file .github/tasks/auth-02.md  # -> #2
gh issue create --title "Signup endpoint and form"          --parent 1 --blocked-by 2 --body-file .github/tasks/auth-03.md  # -> #3
gh issue create --title "Login and session persistence"     --parent 1 --blocked-by 2 --body-file .github/tasks/auth-04.md  # -> #4
gh issue create --title "Logout"                            --parent 1 --blocked-by 4 --body-file .github/tasks/auth-05.md  # -> #5
```

A task body stays small and avoids the how. The acceptance criteria are the contract; the implementer decides the method at build time:

```
<!-- .github/tasks/auth-04.md -->
## Description
Authenticate a returning user and keep them logged in across visits.

## Acceptance criteria
- Valid email and password returns an authenticated session
- The session persists across browser restarts
- Invalid credentials are rejected without revealing which field was wrong

## Checks
- tests/acceptance/test_login.py

## Non-goals
- Does not handle signup (that is #3)
- Does not handle logout (that is #5)
```

## 4. The checks

Each task gets its branch, and the branch's first commit holds the checks, one per criterion. They test what an observer would see, not how the code is built, so they leave the method open:

```
git switch -c task/4 origin/main
# tests/acceptance/test_login.py — one test per criterion of #4
git add tests/acceptance/test_login.py
git commit -m "checks: #4"
git push -u origin task/4
```

The checks are fixed for the implementer: an implementer commit that touches them fails the gate. Only the orchestrator may rewrite them, with a later `checks: #4` commit, and only when they misread the spec.

## 5. The resulting graph

```
#1  Epic 001: User authentication          [epic]
├─ #2  User schema and password hashing    ready
├─ #3  Signup endpoint and form            blocked by #2
├─ #4  Login and session persistence       blocked by #2
└─ #5  Logout                              blocked by #4
```

## 6. Find ready work

Read the list of child issues, not the summary counter:

```
for n in $(gh issue view 1 --json subIssues -q '.subIssues.nodes[].number'); do
  blockers=$(gh issue view "$n" --json blockedBy -q '[.blockedBy.nodes[] | select(.state=="OPEN")] | length')
  state=$(gh issue view "$n" --json state -q .state)
  held=$(gh issue view "$n" --json labels -q '[.labels[].name] | any(. == "needs-human" or . == "in-progress")')
  git ls-remote --exit-code --heads origin "task/$n" >/dev/null || continue
  [ "$state" = "OPEN" ] && [ "$blockers" -eq 0 ] && [ "$held" = "false" ] && echo "ready -> #$n"
done
```

Early on this prints `#2` alone. Merge it and run again: `#3` and `#4` are ready, and can run at once. Merge `#4`: `#5` is ready. The queue is derived from the graph, never maintained by hand.

## 7. Work a task

An implementer takes `#4` on `task/4`, builds until the checks pass, and opens a PR whose description is its report. The gate proves the criteria, so the report only says what the checks cannot:

```
Closes #4

### Skipped
- none

### Unsure
- Session lifetime set to 30 days; the spec names none
```

GitHub runs `gate`. A reviewer, shown only the spec, the sub-issue, and the diff, posts its verdict:

```
Verdict: pass

Stays inside #4: no signup or logout code, no reset flow. The 30-day lifetime is a choice the spec leaves open.
```

`gate` passes and the verdict reads `Verdict: pass`, so the orchestrator merges the PR and `#4` closes. It notes the 30-day choice as a decision in its final report rather than asking. A failure gives the task one more attempt with what failed; on a second failure the orchestrator retries fresh, splits the task, or fixes checks that misread the spec. Only a third failure parks it with `needs-human`.

`#5` is blocked only by `#4`, so it is the next task in the chain: the session that built login continues to logout without rereading the codebase. `#3` sits on a branch of the graph, so a separate session takes it in parallel. When `#3` and `#5` have both merged, the orchestrator closes `#1` and moves to the next approved epic.

## Cross-epic dependencies

Epics block other epics the same way tasks do. If a "User profile" epic cannot start until authentication ships:

```
gh issue edit <profile-epic#> --add-blocked-by 1
```

Containment and dependency are separate graphs. Parent and child say what is part of what; blocking edges say what waits on what, at any level.
