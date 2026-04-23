---
description: Autonomous ship — AI commit, push, PR, watch checks, squash merge, cleanup worktree
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

1. Run: `git add -A`
2. Analyze the diff and generate a commit message in **conventional commits** format:
   - `feat:` — new functionality
   - `fix:` — bug fix
   - `refactor:` — structural change without behavior change
   - `docs:` — documentation
   - `test:` — tests
   - `chore:` — config, deps, build
   - The subject should describe **WHY**, not **WHAT**.
3. Run: `git commit -m "<generated-message>"`

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

Run: `gh pr merge --squash --subject "<commit-message>" --delete-branch`

**Note:** If this fails with `fatal: 'main' is already used by worktree at ...`, that is expected — the PR is still merged and the remote branch is deleted. The local branch will be cleaned up in Step 8. Proceed to Step 8.

## Step 8: Cleanup worktree

1. Get worktree name: `basename $(pwd)` (assumes directory name = wtp worktree name)
2. Check if worktree is clean. If `git status --short` returns anything — STOP with warning "Worktree is dirty, skipping cleanup. Handle manually." and do NOT run `wtp rm`.
3. If clean — switch to base worktree and remove from there: `cd $(wtp cd @) && wtp rm --with-branch <worktree-name>`

## Summary

Print:
- Branch: `<branch>` → `<base>`
- Commit: `<message>`
- PR URL: `<url>`
- Status: `shipped` or `failed at checks` (depending on path taken)
