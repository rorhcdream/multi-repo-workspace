---
name: task-clean
description: This skill should be used when the user asks to "clean up a task", "remove task", "finish task", "delete worktrees", or wants to clean up completed task worktrees and directories. Accepts a task name, a tmux window number (e.g. "3" — resolves to that window's name), or a natural language description.
allowed-tools: Bash, Read, Glob, Grep
---

Clean up a completed task in the multi-repo workspace.

Task to clean: $ARGUMENTS

## Steps

1. **Find workspace root** by locating the `.workspace` marker.

2. **Identify the task.**
   - If `$ARGUMENTS` is a plain integer (e.g. `3`), treat it as a tmux window number and resolve the task name from the window name:
     ```bash
     task_name=$(tmux display-message -p -t <number> '#W')
     ```
     Verify that `<workspace>/tasks/$task_name/` exists. If not, fall back to listing and asking.
   - If `$ARGUMENTS` is a task name or description, use it directly.
   - If `$ARGUMENTS` is empty and the current working directory is inside `<workspace>/tasks/<task-name>/`, use that task name. Before cleanup, `cd <workspace>` so subsequent commands don't run inside the soon-to-be-deleted directory.
   - If `$ARGUMENTS` is empty and not in a task directory, list active tasks and ask the user:
     ```bash
     ls <workspace>/tasks/
     ```

3. **Check for uncommitted changes** in each worktree before removing:
   ```bash
   for dir in <workspace>/tasks/<task-name>/*/; do
     if [ -e "$dir/.git" ]; then
       echo "=== $(basename $dir) ==="
       git -C "$dir" status --short
     fi
   done
   ```
   If there are uncommitted changes, warn the user and ask for confirmation before proceeding. Pass `--force` to the cleanup script (step 4) only after the user confirms.

4. **Assess each branch's merge status — before running the cleanup script.** GitHub's PR merge state is the authoritative signal (it knows about squash *and* rebase merges, which local history can't show). Query it so you have the branch→repo mapping and a full picture up front.
   ```bash
   for dir in <workspace>/tasks/<task-name>/*/; do
     [ -e "$dir/.git" ] || continue
     branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
     repo=$(dirname "$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)")
     echo "=== $(basename "$dir") | $branch ==="
     gh -R "$(git -C "$repo" remote get-url origin)" pr list \
       --head "$branch" --state all --json number,state,mergedAt,title
   done
   ```
   (`gh -R` accepts the origin URL directly, so there's no need to parse out `owner/repo`.) Classify each branch:
   - `"state": "MERGED"` (non-null `mergedAt`) → merged; safe to delete in step 6.
   - `OPEN`, or no PR → keep; do not delete.
   - `gh` unavailable, repo not on GitHub, or the user says it was merged elsewhere → fall back to trusting the user after confirming. Don't insist a branch is unmerged just because `git branch -d` later fails.

5. **Run the cleanup script.** It removes worktrees, closes the tmux window, deletes the task directory, prunes stale worktree refs, and deletes branches it can confirm merged from local history — all in one step. **Run with `dangerouslyDisableSandbox: true`** — it writes to the source repos' `.git/` directories and kills the tmux window, which the sandbox blocks.
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task-clean.sh "<workspace>" "<task-name>" [--force]
   ```
   - Aborts if any worktree has uncommitted changes unless `--force` is passed — so the step 3 check is your safety gate.
   - For branch deletion it only runs `git branch -d`, which catches fast-forward / merge-commit merges. It does **not** attempt to detect squash or rebase merges — those aren't visible in local history (a squash replaces the branch's commits with one new commit on the default branch, so the originals are never ancestors of origin). Any branch it can't confirm this way is reported as kept and resolved by PR status in step 6.

6. **Delete remaining merged branches.** For each branch you classified `MERGED` in step 4 that the script reports as kept (e.g. a rebase merge, or one the patch-id heuristic missed), delete it now that its worktree is gone:
   ```bash
   git -C <workspace>/repos/<category>/<repo> branch -D <branch>
   ```

7. **Report** what was cleaned up — the script's deleted/kept lists, any branches you deleted in step 6, and any kept because their PR is still open.
