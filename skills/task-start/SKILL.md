---
name: task-start
description: Start a new task in the multi-repo workspace. Creates a task directory, writes the prompt, and launches an agent (Claude Code or Codex) in a tmux window.
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, Grep
---

Start a new task in the multi-repo workspace.

Task: $ARGUMENTS

## Steps

1. **Find workspace root** by locating the `.workspace` marker in the current directory or ancestors. If not found, tell the user to run `/workspace-init` first.

2. **Pick the agent.** Default is Claude Code. If the description contains a `--codex` flag, use Codex instead — strip the flag from the text before generating the task name and prompt, and pass `--agent codex` to the setup script.

3. **Generate a task name** from the natural language description:
   - 2-4 words, kebab-case
   - Descriptive of the goal (e.g., "fix-login-timeout", "add-retry-logic")

4. **Run the setup script** to create the task directory, config, instructions doc, prompt file, and launch the agent:
   ```bash
   # Claude (default):
   ${CLAUDE_PLUGIN_ROOT}/scripts/task-setup.sh "<workspace>" "<task-name>" "<prompt>"
   # Codex (when --codex was passed):
   ${CLAUDE_PLUGIN_ROOT}/scripts/task-setup.sh --agent codex "<workspace>" "<task-name>" "<prompt>"
   ```
   The script creates:
   - Task directory at `<workspace>/tasks/<task-name>/`
   - Claude: `.claude/settings.local.json` (sandbox config + Read permission for repos/) and `CLAUDE.md`
   - Codex: `AGENTS.md`; the agent is launched with `--sandbox workspace-write`, which keeps `repos/` read-only and the task dir writable
   - `prompt.md` (raw user prompt, verbatim)
   - Pre-trusts the task dir (Claude: `~/.claude.json`; Codex: `~/.codex/config.toml`)
   - Launches the agent in a new tmux window (or prints instructions if not in tmux)

5. **If already running inside the task directory**, proceed with the task:
   - Read across `<workspace>/repos/` freely to understand the problem
   - Search for relevant code, configs, and documentation
   - Identify which repos will need changes
   - When you need to write to a repo, create a worktree branched from the latest `origin/<default>` using the helper script:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-add.sh <workspace> <task-name> <category> <repo> <branch-desc>
     ```
   - Edit files under the worktree (e.g., `./<repo>/`), not under `<workspace>/repos/`

## Important

- Do NOT investigate or explore the codebase before creating the task. This skill's job is to set up the task directory and delegate work to the spawned agent. Go directly to creating the directory and launching the agent.
- Do NOT create worktrees upfront. Only when you first need to write to a repo.
- Do NOT pull repos automatically. The user will ask if they want updates.
- Reading repos/ is free and unrestricted. Use it extensively for context.
- Under Claude, the Bash sandbox blocks shell writes outside the task directory and a PreToolUse hook blocks Edit/Write to repos/. Under Codex, the `workspace-write` sandbox makes everything outside the task directory (including repos/) read-only. Either way, repos/ stays read-only.
