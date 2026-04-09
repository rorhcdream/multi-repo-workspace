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

3. **Create the task directory with repos symlink and sandbox config:**
   ```bash
   mkdir -p <workspace>/tasks/<task-name>/.claude
   ln -sfn <workspace>/repos <workspace>/tasks/<task-name>/repos
   ```
   The `repos` symlink gives convenient read access to all source repos from within the task directory.

   Create `.claude/settings.local.json` to enable the sandbox and allow reading repos/:
   ```json
   {
     "permissions": {
       "allow": [
         "Read(//<workspace-absolute-path>/repos/**)"
       ]
     },
     "sandbox": {
       "enabled": true,
       "filesystem": {
         "allowRead": ["<workspace>/repos"],
         "allowWrite": ["<workspace>/repos"]
       }
     }
   }
   ```
   The `permissions.allow` grants the Read tool access to repos/ without prompting. The `//` prefix marks it as an absolute filesystem path (a single `/` is interpreted as relative). Since `<workspace>` is already an absolute path starting with `/`, the result should be exactly two slashes: `//Users/...`, not three. The `sandbox.filesystem` grants Bash read/write access (needed for `git worktree add` which writes to `.git/`). The PreToolUse hook blocks Edit/Write tool calls to repos/ files, so content remains read-only — only git CLI operations are allowed through.

4. **Create `CLAUDE.md`** in the task directory to orient the spawned Claude:
   ```markdown
   # Task: <task-name>

   ## Workspace layout

   - `repos/` — Symlink to source repos. **Read-only.** Browse freely for context.
   - `./<repo>/` — Git worktrees you create for this task. Edit files here.

   ## Workflow

   1. Read across `repos/` to understand the problem.
   2. When you need to modify a repo, create a worktree:
      ```bash
      git -C <workspace>/repos/<category>/<repo> worktree add \
        <workspace>/tasks/<task-name>/<repo> -b <task-name>/<branch-desc>
      ```
   3. Edit files under `./<repo>/`, never under `repos/`.
   4. You can create worktrees for multiple repos if the task spans them.

   ## Rules

   - Do NOT edit files under `repos/` — a hook will block you.
   - Do NOT create worktrees upfront. Only when you first need to write to a repo.
   ```
   Replace `<workspace>`, `<task-name>`, `<category>`, and `<repo>` with actual values. The category/repo structure matches how repos are organized under `repos/`.

5. **Create a prompt file** with the raw user prompt as-is:
   Write `$ARGUMENTS` verbatim to `<workspace>/tasks/<task-name>/prompt.md`. Do NOT summarize, rephrase, or interpret — pass the user's exact words so the spawned Claude gets full context.

6. **Launch in a new tmux window** (if inside tmux):
   ```bash
   if [ -n "$TMUX" ]; then
     # Create a new tmux window with a shell (not claude directly, since launching
     # claude as tmux's command causes the window to close if claude exits)
     tmux new-window -n "<task-name>" -c "<workspace>/tasks/<task-name>"
     tmux set-window-option -t "<task-name>" automatic-rename off
     # Send the claude command to the shell so it stays alive after claude exits
     # With prompt file (use $(cat prompt.md) to pass content as argument):
     tmux send-keys -t "<task-name>" 'claude "$(cat prompt.md)"' Enter
     # Without prompt file (short/vague description):
     tmux send-keys -t "<task-name>" 'claude' Enter
   fi
   ```
   This creates a new tmux window with a shell, then sends the claude command to it. The shell survives if claude exits, so the user can relaunch.

   If not inside tmux, tell the user:
   ```
   cd <workspace>/tasks/<task-name>
   claude "$(cat prompt.md)"
   ```
   Launching from the task directory means the Bash sandbox automatically restricts writes to the task directory. Repos are readable via the `repos/` symlink but not writable via Bash. The PreToolUse hook separately blocks Edit/Write to repos/.

7. **If already running inside the task directory**, proceed with the task:
   - Read across `repos/` freely to understand the problem
   - Search for relevant code, configs, and documentation
   - Identify which repos will need changes
   - When you need to write to a repo, create a worktree:
     ```bash
     git -C <workspace>/repos/<category>/<repo> worktree add \
       <workspace>/tasks/<task-name>/<repo> -b <task-name>/<branch-desc>
     ```
   - Edit files under the worktree (e.g., `./<repo>/`), not under `repos/`

## Important

- Do NOT investigate or explore the codebase before creating the task. This skill's job is to set up the task directory and delegate work to the spawned Claude instance. Go directly to creating the directory and launching Claude.
- Do NOT create worktrees upfront. Only when you first need to write to a repo.
- Do NOT pull repos automatically. The user will ask if they want updates.
- Reading repos/ is free and unrestricted. Use it extensively for context.
- The Bash sandbox blocks shell writes outside the task directory. The PreToolUse hook blocks Edit/Write to repos/. Together they enforce repos/ as read-only.
