---
description: gh-ship — commit, push, watch checks, merge. Supports main & feature branches.
agent: build
subtask: true
---

User arguments: "$ARGUMENTS"

Parse arguments:
- If `$ARGUMENTS` starts with `--dry-run` (or `-d`):
  - Set `dry_run = true`
  - The remainder (after stripping the flag and optional space) is the optional commit message
- Otherwise:
  - `dry_run = false`
  - The entire `$ARGUMENTS` is the optional commit message

## Start context

Current branch: !`git branch --show-current`
Base branch: !`gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo 'main'`
Git status: !`git status --short`
Staged diff stat: !`git diff --cached --stat`
Unstaged diff stat: !`git diff --stat`

## Step 0: Determine mode

Set `mode = main` if current branch is `main` or `master`. Otherwise `mode = feature`.

## Step 1: Validation

- If there are no changes (neither staged nor unstaged nor untracked) — STOP with error "No changes to ship".
- Verify git identity:
  - `git config user.name` and `git config user.email` must be present and non-empty.
  - If missing, STOP with error "Git user.name/user.email not configured properly. Run: git config user.name 'Your Name' && git config user.email 'your@email.com'"

## Step 2: Commit

1. `git add -A`
2. If nothing staged after add, STOP.
3. Determine commit message:
   - If user provided a message via arguments, use it.
   - Otherwise, analyze the diff and generate a conventional commit message (feat:/fix:/refactor:/docs:/test:/chore:). Describe WHY, not WHAT.
4. If `dry_run` is true, print `[dry-run] Would commit: <message>` and skip to the appropriate watch step (Step 4 for feature, Step 5 for main).
5. Otherwise: `git commit -m "<message>"`

## Step 3: Push

If `dry_run`:
- Print `[dry-run] Would push to origin/<branch>`
- Skip to watch step.

Otherwise:
- If `mode == feature`: `git push -u origin <branch>`
- If `mode == main`: `git push origin <branch>`
- Record the pushed commit SHA (`git rev-parse HEAD`).

## Step 4 (Feature mode): Create PR

If `dry_run`:
- Print `[dry-run] Would create PR with title: <commit-subject>`
- Skip to watch step.

Otherwise:
1. Generate PR title (max 72 chars, same as commit subject or extended).
2. Generate minimal body:
   ```markdown
   ## Summary
   [1-2 sentences WHY]

   ## Changes
   - [key change 1]
   - [key change 2]
   ```
3. `gh pr create --title "<title>" --body "<body>"`
4. Fetch PR URL: `gh pr view --json url --jq '.url'`

## Step 5: Watch checks

### Feature mode

Run: `gh pr checks --watch --fail-fast --interval 30`

- If exit 0: go to Step 7 (Merge).
- If exit non-0: go to Step 6 (Fail path).

### Main mode

1. Wait for the GitHub Actions run to appear for this branch + commit:
   ```bash
   run_id=$(gh run list --branch=<branch> --commit=<sha> --limit=1 --json databaseId --jq '.[0].databaseId')
   ```
   Poll every 5 seconds, max 120 seconds.
2. Run: `gh run watch <run_id> --exit-status`

- If exit 0: go to Step 7 (Done).
- If exit non-0: go to Step 6 (Fail path).

## Step 6: Fail path — fixup loop

**Do NOT make code changes without asking the user first.**

1. Get failing check details: `gh pr checks --json name,state,bucket,link` (feature) or `gh run view <run_id> --log-failed` (main).
2. Present a summary to the user:
   - Which check failed
   - Why it failed (from logs)
   - Suggested fix
3. Ask the user: "Fix the issues, then I will amend, force-push and re-watch. Continue? [y/N]"
4. If user says yes:
   - `git add -A`
   - `git commit --amend --no-edit`
   - Verify remote has not moved since our push. If it has, abort with error.
   - `git push --force-with-lease origin <branch>`
   - Go back to Step 5 (Watch checks).
5. If user says no: STOP with "Stopped. Fix manually and re-run /gh-ship."

## Step 7: Finalize

### Feature mode

If `dry_run`:
- Print `[dry-run] Would squash-merge PR and delete branch`
- STOP.

Otherwise:
- `gh pr merge --squash --delete-branch`
- Print success summary.

### Main mode

Print success summary. No merge needed (already on main).

## Step 8: Retrospective

Before printing the final summary, analyze the full execution:
- Did any step require a retry, workaround, or manual override?
- Did checks pass on the first run or fail and require intervention?
- Were there any unexpected errors?
- What decisions did you make in edge cases and why?

Summarize these findings in 2-4 sentences.

## Summary

Print:
- Branch: `<branch>` -> `<base>`
- Commit: `<message>`
- PR URL: `<url>` (feature mode only)
- Status: `shipped` or `failed at checks`

Then append the retrospective.
