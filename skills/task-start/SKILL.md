---
name: task-start
description: Start a new task in the multi-repo workspace through a background worker. Creates a task directory, writes the prompt, and launches an agent in a tmux window (directly by default, or inside Neovim with --nvim). Use only when the user explicitly invokes `/task-start` — never invoke this on your own initiative.
allowed-tools: Read, Write, Bash, Glob, Grep, Agent
---

Start a new task in the multi-repo workspace.

Task: $ARGUMENTS

> **Codex compatibility**: `${CLAUDE_PLUGIN_ROOT}` is Claude Code's plugin-root variable — under Codex, substitute this plugin's root directory (two levels above this SKILL.md). Steps that say to run with `dangerouslyDisableSandbox: true` mean, under Codex, running the command with escalated permissions (approve the sandbox escalation).

## Background dispatch

Unless the invocation identifies you as the **task-start background worker**, do not execute the setup steps in the foreground.

1. Launch exactly one general-purpose subagent in the background. Under Claude Code, use the `Agent` tool with `run_in_background: true`. Under Codex, use the available subagent spawning capability and leave it running without waiting or polling.
2. Give it the original `$ARGUMENTS`, the current working directory, and this instruction: `You are the task-start background worker. Execute the task-start skill steps directly. Do not delegate or spawn another worker. Report completion or a blocker when finished.`
3. Tell the user that task creation was dispatched, then end the foreground turn immediately so another command can be issued.

If background subagents are unavailable, report that limitation and stop. Do not silently run the workflow in the foreground.

If you are the marked task-start background worker, skip this section and execute the steps below directly.

## Steps

1. **Find workspace root** by locating the `.workspace` marker in the current directory or ancestors. If not found, tell the user to run `/workspace-init` first.

2. **Pick the agent and launch mode.** Both default from the environment (`MRW_AGENT`, `MRW_NVIM`) — do NOT read or second-guess those variables, just forward the flags the user passed and let the script apply its own defaults. Strip any flags from the text before generating the task name and prompt:
   - `--claude` / `--codex`: pass the same flag through to the setup script.
   - `--nvim` / `--no-nvim`: pass the same flag through to the setup script.
   - No flag: pass none, so the environment default applies.

3. **Generate a task name** that describes the goal:
   - 2-4 words, kebab-case, descriptive of the goal (e.g., "fix-login-timeout", "add-retry-logic")
   - If the description already states the goal, derive the name from it directly — no lookup needed.
   - If the description is only an opaque reference (issue/ticket ID, URL, PR number, commit hash), resolve it to a title first using whatever tool is available — an issue-tracker MCP tool, `gh issue view` / `gh pr view`, or `git log` for a commit — and name the task from that summary. Keep the reference as a prefix for traceability, e.g. `proj-123-fix-login-timeout`.
   - If the reference cannot be resolved with available tools, ask the user for a few words describing the goal rather than using the opaque ID as the name.

4. **Run the setup script** to create the task directory, config, instructions doc, prompt file, and launch the agent:
   ```bash
   # No flags — environment defaults apply:
   ${CLAUDE_PLUGIN_ROOT}/scripts/task-setup.sh "<workspace>" "<task-name>" "<prompt>"
   # With flags — any combination, forwarded verbatim from the user's request:
   ${CLAUDE_PLUGIN_ROOT}/scripts/task-setup.sh --claude --no-nvim "<workspace>" "<task-name>" "<prompt>"
   ```
   The script creates:
   - Task directory at `<workspace>/tasks/<task-name>/`
   - Claude: `.claude/settings.local.json` (sandbox config + Read permission for repos/) and `CLAUDE.md`
   - Codex: `AGENTS.md`; the agent is launched with `--sandbox workspace-write`, which keeps `repos/` read-only and the task dir writable
   - `prompt.md` (raw user prompt, verbatim)
   - Pre-trusts the task dir (Claude: `~/.claude.json`; Codex: `~/.codex/config.toml`)
   - Launches the agent in a new tmux window with `prompt.md` (or prints the equivalent command if not in tmux). In Neovim mode, the window runs Neovim, selects the requested Sidecar agent, then submits `prompt.md` with `SidecarPromptFile!` from a non-blocking callback after a two-second initialization delay.

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

- Do NOT investigate or explore the codebase before creating the task. This skill's job is to set up the task directory and delegate work to the spawned agent. Go directly to creating the directory and launching the agent. The only exception is the bounded reference lookup in step 3 (a single title fetch for naming — not code exploration).
- Do NOT create worktrees upfront. Only when you first need to write to a repo.
- Do NOT pull repos automatically. The user will ask if they want updates.
- Reading repos/ is free and unrestricted. Use it extensively for context.
- Under Claude, the Bash sandbox blocks shell writes outside the task directory and a PreToolUse hook blocks Edit/Write to repos/. Under Codex, the `workspace-write` sandbox makes everything outside the task directory (including repos/) read-only. Either way, repos/ stays read-only.
