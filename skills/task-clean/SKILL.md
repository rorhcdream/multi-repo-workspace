---
name: task-clean
description: This skill should be used when the user asks to "clean up a task", "remove task", "finish task", "delete worktrees", or wants to clean up completed task worktrees and directories. Accepts a task name or natural language description.
allowed-tools: Bash, Read, Glob, Grep
---

Clean up a completed task in the multi-repo workspace.

Task to clean: $ARGUMENTS

## Steps

1. **Find workspace root** by locating the `.workspace` marker.

2. **Identify the task.** If no specific task is named, list active tasks and ask the user:
   ```bash
   ls <workspace>/tasks/
   ```

3. **Check for uncommitted changes** in each worktree before removing:
   ```bash
   for dir in <workspace>/tasks/<task-name>/*/; do
     if [ -f "$dir/.git" ]; then
       echo "=== $(basename $dir) ==="
       git -C "$dir" status --short
     fi
   done
   ```
   If there are uncommitted changes, warn the user and ask for confirmation before proceeding.

4. **Record branch names** before removing worktrees (needed for cleanup):
   ```bash
   for dir in <workspace>/tasks/<task-name>/*/; do
     if [ -f "$dir/.git" ]; then
       branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
       echo "$(basename $dir): $branch"
     fi
   done
   ```
   Save the repo-to-branch mapping for step 7.

5. **Remove each worktree** properly (skip the `repos` symlink):
   ```bash
   for dir in <workspace>/tasks/<task-name>/*/; do
     [ -L "$dir" ] && continue  # skip symlinks (repos/)
     if [ -f "$dir/.git" ]; then
       git worktree remove "$dir"
     fi
   done
   ```

6. **Remove the task directory:**
   ```bash
   rm -rf <workspace>/tasks/<task-name>
   ```

7. **Clean up task branches.** For each branch recorded in step 4, check if it was merged and delete it:
   ```bash
   # For each repo/branch pair from step 4:
   git -C <workspace>/repos/<category>/<repo> branch --merged | grep -q "<branch>"
   # If merged, safe to delete:
   git -C <workspace>/repos/<category>/<repo> branch -d <branch>
   # If NOT merged, warn the user and ask before deleting with -D
   ```
   Always inform the user which branches were deleted and which were kept.

8. **Prune stale worktree references** in source repos:
   ```bash
   for repo in <workspace>/repos/*/*/; do
     if [ -d "$repo/.git" ]; then
       git -C "$repo" worktree prune
     fi
   done
   ```

9. **Report** what was cleaned up, including which branches were deleted and which were kept.
