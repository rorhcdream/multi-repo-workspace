---
name: task-start
description: This skill should be used when the user asks to "start a task", "begin working on", "fix this issue", "implement this feature", or describes work to do across one or more repos in the multi-repo workspace. Accepts a natural language task description, creates a task directory, and begins investigation with lazy worktree creation.
allowed-tools: Read, Write, Bash, Glob, Grep
---

Start a new task in the multi-repo workspace.

Task: $ARGUMENTS

## Steps

1. **Find workspace root** by locating the `.workspace` marker in the current directory or ancestors. If not found, tell the user to run `/workspace-init` first.

2. **Generate a task name** from the natural language description:
   - 2-4 words, kebab-case
   - Descriptive of the goal (e.g., "fix-login-timeout", "add-retry-logic")

3. **Create the task directory, add a repos symlink, and configure tmux window:**
   ```bash
   mkdir -p <workspace>/tasks/<task-name>
   ln -sfn <workspace>/repos <workspace>/tasks/<task-name>/repos
   ```
   If running inside tmux, rename the current window to the task name and disable automatic renaming:
   ```bash
   if [ -n "$TMUX" ]; then
     tmux rename-window "<task-name>"
     tmux set-window-option automatic-rename off
   fi
   ```

4. **Investigate the task.** Read across repos/ freely to understand the problem:
   - Search for relevant code, configs, and documentation
   - Understand the codebase structure and dependencies
   - Identify which repos will need changes

5. **When you need to write to a repo**, create a worktree:
   ```bash
   git -C <workspace>/repos/<category>/<repo> worktree add \
     <workspace>/tasks/<task-name>/<repo> -b <task-name>/<branch-desc>
   ```
   Then edit files under `tasks/<task-name>/<repo>/`.

6. **Work on the task.** Continue reading from repos/ and writing to task worktrees as needed. Multiple repos can be modified — each gets its own worktree.

## Important

- Do NOT create worktrees upfront. Only when you first need to write to a repo.
- Do NOT pull repos automatically. The user will ask if they want updates.
- Reading repos/ is free and unrestricted. Use it extensively for context.
- The PreToolUse hook will block writes to repos/ as a safety net and remind you to create a worktree.
