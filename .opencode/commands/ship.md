---
description: Ship current changes — commit, push, watch checks, merge
agent: build
---

Ship the current working-tree changes using the project's preferred tool.

**Primary path:**
1. Check if `bin/ship` exists and is executable.
2. If yes, run `bin/ship ship` (optionally with `--dry-run` first if the user seems unsure).
3. Let `bin/ship` handle everything: commit, push, PR creation (if on a feature branch), check watching, merge/squash, and cleanup.

**Fallback path (only if `bin/ship` is missing or fails):**
1. If on `main`/`master`:
   - `git add -A && git commit -m "..." && git push origin main`
   - Wait for the GitHub Actions run to complete (`gh run watch` or monitor via `gh run list`).
2. If on a feature branch:
   - `git add -A && git commit -m "..."`
   - `git push -u origin <branch>`
   - `gh pr create --title "..." --body "..."`
   - `gh pr checks --watch --fail-fast`
   - `gh pr merge --squash --delete-branch`
3. If checks fail and the user wants to fix:
   - On main: amend + `git push --force-with-lease origin main`
   - On feature branch: amend + `git push --force-with-lease origin <branch>`, then re-watch checks.

Always prefer `bin/ship` when available.
