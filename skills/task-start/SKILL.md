---
name: task-start
description: Start a new task in the multi-repo workspace. Creates a task directory, writes the prompt, and launches Claude Code in a tmux window.
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, Grep
---

Start a new task in the multi-repo workspace.

Task: $ARGUMENTS

## Steps

1. **Find workspace root** by locating the `.workspace` marker in the current directory or ancestors. If not found, tell the user to run `/workspace-init` first.

2. **Generate a task name** from the natural language description:
   - 2-4 words, kebab-case
   - Descriptive of the goal (e.g., "fix-login-timeout", "add-retry-logic")

3. **Run the setup script** to create the task directory, config, CLAUDE.md, prompt file, and launch Claude:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task-setup.sh "<workspace>" "<task-name>" "$ARGUMENTS"
   ```
   The script creates:
   - Task directory at `<workspace>/tasks/<task-name>/`
   - `.claude/settings.local.json` (sandbox config + Read permission for repos/)
   - `CLAUDE.md` (workspace layout and workflow instructions)
   - `prompt.md` (raw user prompt, verbatim)
   - Launches Claude in a new tmux window (or prints instructions if not in tmux)

4. **If already running inside the task directory**, proceed with the task:
   - Read across `<workspace>/repos/` freely to understand the problem
   - Search for relevant code, configs, and documentation
   - Identify which repos will need changes
   - When you need to write to a repo, create a worktree:
     ```bash
     git -C <workspace>/repos/<category>/<repo> worktree add \
       <workspace>/tasks/<task-name>/<repo> -b <task-name>/<branch-desc>
     ```
   - Edit files under the worktree (e.g., `./<repo>/`), not under `<workspace>/repos/`

## Important

- Do NOT investigate or explore the codebase before creating the task. This skill's job is to set up the task directory and delegate work to the spawned Claude instance. Go directly to creating the directory and launching Claude.
- Do NOT create worktrees upfront. Only when you first need to write to a repo.
- Do NOT pull repos automatically. The user will ask if they want updates.
- Reading repos/ is free and unrestricted. Use it extensively for context.
- The Bash sandbox blocks shell writes outside the task directory. The PreToolUse hook blocks Edit/Write to repos/. Together they enforce repos/ as read-only.
