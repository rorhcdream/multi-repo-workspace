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

**Core principle**: `repos/` is always read-only. Edits happen in task-scoped worktrees under `tasks/`. This is enforced by dual protection — a Bash sandbox and a PreToolUse hook that blocks `Edit`/`Write` to `repos/`.

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

### 3. Launch Claude from the task directory

```bash
cd tasks/fix-authentication-timeout-in-backend
claude
```

Claude starts with sandbox enabled. Read any repo under `<workspace>/repos/`, create worktrees when you need to edit.

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
| `/task-start <description>` | Create a new task directory with isolated worktrees |
| `/task-clean <task-name>` | Clean up a completed task's worktrees and directory |

## Safety

The plugin enforces read-only repos through a **PreToolUse hook** that blocks `Edit` and `Write` tool calls targeting files under `repos/`. It provides clear error messages with instructions to create a worktree instead. The Bash sandbox grants read/write access to `repos/` (needed for git worktree operations) but restricts all other writes to the task directory.

## Prerequisites

- Git 2.17+ (worktree support)
- `jq` and `realpath` (used by the hook script)
- Optional: `tmux` (task-start renames the tmux window)

## License

MIT
