---
description: gh-ship — AI commit, push, PR, watch checks, squash merge, cleanup worktree
agent: build
subtask: true
---

You are an autonomous ship bot. Execute the following steps sequentially for the current branch/worktree. Do not skip any step.

## Start context

Current branch: !`git branch --show-current`
Base branch: !`gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo 'main'`
Git status: !`git status --short`
Staged diff stat: !`git diff --cached --stat`
Unstaged diff stat: !`git diff --stat`

## Step 1: Validation

- If the current branch is `main` or `master` — STOP with error "Cannot ship from main/master".
- If there are no changes (neither staged nor unstaged) — STOP with error "No changes to ship".

## Step 2: AI commit

1. Verify git identity is configured:
   - `git config user.name` — should return the user's name
   - `git config user.email` — should return the user's email
   - If either is missing or looks like a bot/system default, STOP with error "Git user.name/user.email not configured properly. Run: git config user.name 'Your Name' && git config user.email 'your@email.com'"
2. Run: `git add -A`
3. Analyze the diff and generate a commit message in **conventional commits** format:
   - `feat:` — new functionality
   - `fix:` — bug fix
   - `refactor:` — structural change without behavior change
   - `docs:` — documentation
   - `test:` — tests
   - `chore:` — config, deps, build
   - The subject should describe **WHY**, not **WHAT**.
4. Run: `git commit -m "<generated-message>"`

## Step 3: Push

Run: `git push -u origin <branch>`

## Step 4: Create PR

1. Generate a PR title (same as commit or extended, max 72 chars).
2. Generate minimal body:

```markdown
## Summary
[1-2 sentences WHY]

## Changes
- [key change 1]
- [key change 2]
```

3. Create PR: `gh pr create --title "<title>" --body "<body>"`
4. Fetch and remember the PR URL: `gh pr view --json url --jq '.url'`

## Step 5: Watch checks

Run: `gh pr checks --watch --fail-fast --interval 30`

If exit code is 0 — go to Step 7 (Merge).
If exit code is not 0 — go to Step 6 (Fail path).

## Step 6: Fail path — debug, plan fix, do NOT auto-fix

**Do NOT make any code changes. Do NOT merge.**

1. Get failing check details: `gh pr checks --json name,state,bucket,link`
2. If these are GitHub Actions, fetch logs for the failing run (`gh run view --log-failed <run-id>` or via check links).
3. Analyze the source code related to the failures.
4. Present a comprehensive report to the user:
   - **Failing check** (name, link)
   - **Root cause** — diagnosed from logs and code
   - **Fix plan** — exact files and changes to propose
   - **Suggested commands** for the user to run

STOP here. Do not proceed to merge or cleanup.

## Step 7: Squash merge

Run: `gh pr merge --squash --delete-branch`

Note: Do NOT pass `--subject`. GitHub will use the PR title automatically
and append `(#<number>)` to the squash commit subject.

## Step 8: Cleanup worktree

1. Store current worktree path: `worktree_path="$(pwd)"`
2. Resolve the actual branch name for this worktree:
   `branch_name="$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD)"`
   (this is robust even when the directory name does not match the branch)
3. Check if worktree is clean. If `git status --short` returns anything — STOP with warning "Worktree is dirty, skipping cleanup. Handle manually." and do NOT run cleanup.
4. If clean — run in one chained shell:
   ```bash
   cd "$(dirname "$(git -C "$worktree_path" rev-parse --git-common-dir)")" && \
     git worktree remove "$worktree_path" && \
     git branch -D "$branch_name"
   ```

## Step 9: Retrospective

Before printing the final summary, analyze the full execution:
- Did any step require a retry, workaround, or manual override?
- Did checks pass on the first run or fail and require intervention?
- Were there any unexpected errors (e.g., push rejected, dirty worktree, merge conflicts, `fatal: 'main' is already used by worktree`)?
- Did the merge and cleanup succeed without complications?
- What decisions did you make in edge cases and why?

Summarize these findings in 2-4 sentences. Be honest about problems, fixes, or deviations from the happy path.

## Summary

Print:
- Branch: `<branch>` → `<base>`
- Commit: `<message>`
- PR URL: `<url>`
- Status: `shipped` or `failed at checks` (depending on path taken)

Then append the retrospective:
- Retrospective: [your 2-4 sentence analysis of problems, fixes, and decisions]
