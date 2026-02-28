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

4. **Remove each worktree** properly:
   ```bash
   for dir in <workspace>/tasks/<task-name>/*/; do
     if [ -f "$dir/.git" ]; then
       git worktree remove "$dir"
     fi
   done
   ```

5. **Remove the task directory:**
   ```bash
   rm -rf <workspace>/tasks/<task-name>
   ```

6. **Prune stale worktree references** in source repos:
   ```bash
   for repo in <workspace>/repos/*/*/; do
     if [ -d "$repo/.git" ]; then
       git -C "$repo" worktree prune
     fi
   done
   ```

7. **Report** what was cleaned up.
