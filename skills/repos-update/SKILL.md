---
name: repos-update
description: This skill should be used when the user asks to "update repos", "pull repos", "sync repos", "fetch latest", or wants to bring all source repos under `<workspace>/repos/` up to date with their remote default branches.
allowed-tools: Bash
---

Update all source repos in the multi-repo workspace to their remote default branches.

## Steps

1. **Find workspace root** by locating the `.workspace` marker in the current directory or ancestors. If not found, tell the user to run `/workspace-init` first.

2. **Run the update script** with `dangerouslyDisableSandbox: true` (git pull/fetch needs network and credential access):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/repos-update.sh "<workspace>" [repo-name ...]
   ```
   With no repo names it updates every repo. Pass one or more repo names (the `<repo>` dir basename) to update only those — e.g. `... "<workspace>" service-a service-b`.

   For each selected repo under `<workspace>/repos/<category>/<repo>/`:
   - Determines its default branch from `origin/HEAD`
   - If currently on the default branch, runs `git pull --ff-only`
   - Otherwise, runs `git fetch origin <default>:<default>` to update the local default branch ref without touching the working tree
   - Skips repos without a discoverable default branch

3. **Report** the per-repo results to the user.

## Important

- This skill only updates source repos under `repos/`. It does NOT touch task worktrees under `tasks/`.
- Fast-forward only — never rebases or merges. If a repo's local default branch has diverged, the pull will fail loudly and that repo is reported as-is.
