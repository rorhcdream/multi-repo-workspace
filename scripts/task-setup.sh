#!/bin/bash
# Creates a task directory with all necessary config and launches Claude in tmux.
# Usage: task-setup.sh <workspace> <task-name> [prompt-text]
set -euo pipefail

WORKSPACE="$1"
TASK_NAME="$2"
PROMPT="${3:-}"
TASK_DIR="$WORKSPACE/tasks/$TASK_NAME"

# 1. Create directory structure
mkdir -p "$TASK_DIR/.claude"

# 2. Write sandbox config with Read permission for repos/
cat > "$TASK_DIR/.claude/settings.local.json" <<SETTINGS
{
  "permissions": {
    "allow": [
      "Read(/$WORKSPACE/repos/**)",
      "Grep(/$WORKSPACE/repos/**)"
    ]
  },
  "sandbox": {
    "enabled": true,
    "filesystem": {
      "allowRead": ["$WORKSPACE/repos"],
      "allowWrite": ["$WORKSPACE/repos"]
    }
  }
}
SETTINGS

# 3. Write CLAUDE.md
cat > "$TASK_DIR/CLAUDE.md" <<CLAUDEMD
# Task: $TASK_NAME

## Workspace layout

- \`$WORKSPACE/repos/\` — Source repos. **Read-only.** Browse freely for context.
- \`./\<repo\>/\` — Git worktrees you create for this task. Edit files here.

## Workflow

1. Read across \`$WORKSPACE/repos/\` to understand the problem.
2. When you need to modify a repo, create a worktree. **Run this command with \`dangerouslyDisableSandbox: true\`** — \`git worktree add\` writes to the source repo's \`.git/\` directory, which is outside the task directory and blocked by the sandbox.
   \`\`\`bash
   git -C $WORKSPACE/repos/<category>/<repo> worktree add \\
     $TASK_DIR/<repo> -b $TASK_NAME/<branch-desc>
   \`\`\`
3. Edit files under \`./\<repo\>/\`, never under \`$WORKSPACE/repos/\`.
4. You can create worktrees for multiple repos if the task spans them.

## Rules

- Do NOT edit files under \`$WORKSPACE/repos/\` — a hook will block you.
- Do NOT create worktrees upfront. Only when you first need to write to a repo.
CLAUDEMD

# 4. Write prompt file if provided
if [ -n "$PROMPT" ]; then
  printf '%s\n' "$PROMPT" > "$TASK_DIR/prompt.md"
fi

# 5. Launch in tmux or print instructions
if [ -n "${TMUX:-}" ]; then
  tmux new-window -n "$TASK_NAME" -c "$TASK_DIR"
  tmux set-window-option -t "$TASK_NAME" automatic-rename off
  if [ -n "$PROMPT" ]; then
    tmux send-keys -t "$TASK_NAME" 'claude "$(cat prompt.md)"' Enter
  else
    tmux send-keys -t "$TASK_NAME" 'claude' Enter
  fi
  echo "Launched in tmux window: $TASK_NAME"
else
  echo "Task directory created: $TASK_DIR"
  echo "Run:"
  echo "  cd $TASK_DIR"
  if [ -n "$PROMPT" ]; then
    echo '  claude "$(cat prompt.md)"'
  else
    echo "  claude"
  fi
fi
