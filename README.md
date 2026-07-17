# multi-repo-workspace

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin for managing multiple Git repositories in a single workspace with **copy-on-write semantics via git worktrees**.

Read from all your repos freely. When you need to edit, the plugin creates isolated worktrees per task — keeping source repos untouched.

## How it works

```
<workspace>/
├── repos/                # Read-only clones (organized by category)
│   ├── org/
│   │   ├── backend/
│   │   └── frontend/
│   └── public/
│       └── shared-lib/
├── tasks/                # Isolated task worktrees (copy-on-write)
│   └── fix-auth-bug/
│       ├── backend/      # Git worktree (for editing)
│       └── frontend/     # Git worktree (for editing)
├── .workspace            # Workspace marker file
└── CLAUDE.md             # Auto-generated workspace rules
```

**Core principle**: `repos/` is always read-only. Edits happen in task-scoped worktrees under `tasks/`. Under Claude Code this is enforced by dual protection — a Bash sandbox and a PreToolUse hook that blocks `Edit`/`Write` to `repos/`. Under Codex the `workspace-write` sandbox enforces it: only the task directory is writable, so everything under `repos/` is read-only.

## Installation

```bash
claude plugin marketplace add rorhcdream/multi-repo-workspace
claude plugin install multi-repo-workspace
```

## Quick start

### 1. Initialize a workspace

```
/workspace-init
```

Provide category names (e.g., `org`, `public`, `personal`) and source directories to clone repos from.

### 2. Start a task

```
/task-start fix authentication timeout in backend
```

Creates `tasks/fix-authentication-timeout-in-backend/` configured with read access to `repos/`.

By default the task launches **Claude Code**. Add `--codex` to launch **Codex** instead:

```
/task-start --codex fix authentication timeout in backend
```

### 3. Launch the agent from the task directory

```bash
cd tasks/fix-authentication-timeout-in-backend
claude                          # or: codex --sandbox workspace-write
```

The agent starts sandboxed. Read any repo under `<workspace>/repos/`, create worktrees when you need to edit.

### 4. Clean up when done

```
/task-clean fix-authentication-timeout-in-backend
```

Removes worktrees and the task directory. Warns if there are uncommitted changes.

## Skills

| Skill | Description |
|---|---|
| `/workspace-init` | Initialize a new multi-repo workspace with categories and repo clones |
| `/workspace` | Show workspace status — repos, active tasks, worktree info |
| `/task-start [--codex] <description>` | Create a new task directory with isolated worktrees (add `--codex` to launch Codex instead of Claude Code) |
| `/task-clean <task-name>` | Clean up a completed task's worktrees and directory |

## Safety

**Claude Code**: read-only repos are enforced through a **PreToolUse hook** that blocks `Edit` and `Write` tool calls targeting files under `repos/`, with clear error messages instructing you to create a worktree instead. The Bash sandbox grants read/write access to `repos/` (needed for git worktree operations) but restricts all other writes to the task directory.

**Codex**: the task launches with `--sandbox workspace-write`, so only the task directory (the working root) is writable. Everything under `repos/` is readable but read-only. Creating a worktree and updating repos need network and writes to the source repo's `.git/`, which fall outside the sandbox — approve the escalation when the agent asks (the equivalent of Claude's `dangerouslyDisableSandbox`). Folder trust is pre-seeded in `~/.codex/config.toml` so the task launches without a trust prompt.

## Prerequisites

- Git 2.17+ (worktree support)
- `jq` and `realpath` (used by the hook script)
- Optional: `tmux` (task-start renames the tmux window)
- For `--codex` tasks: the [Codex CLI](https://developers.openai.com/codex/cli) on your `PATH`

## License

MIT
