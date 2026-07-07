#!/bin/bash
# Creates a task directory with all necessary config and launches Claude in tmux.
# Usage: task-setup.sh <workspace> <task-name> [prompt-text]
set -euo pipefail

WORKSPACE="$1"
TASK_NAME="$2"
PROMPT="${3:-}"
TASK_DIR="$WORKSPACE/tasks/$TASK_NAME"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

1. Before reading a repo for context, update it to the latest default branch — but only the repos you'll actually read. **Run with \`dangerouslyDisableSandbox: true\`** (needs network):
   \`\`\`bash
   $SCRIPT_DIR/repos-update.sh "$WORKSPACE" <repo> [<repo> ...]
   \`\`\`
2. Read across \`$WORKSPACE/repos/\` to understand the problem.
3. When you need to modify a repo, create a worktree using the helper script. **Run with \`dangerouslyDisableSandbox: true\`** — it fetches from the remote and writes to the source repo's \`.git/\` directory, both of which the sandbox blocks.
   \`\`\`bash
   $SCRIPT_DIR/worktree-add.sh "$WORKSPACE" "$TASK_NAME" <category> <repo> <branch-desc>
   \`\`\`
   The script fetches origin's default branch first, then creates the worktree branched from \`origin/<default>\` so you always start from the latest \`main\`/\`master\`.
4. Edit files under \`./\<repo\>/\`, never under \`$WORKSPACE/repos/\`.
5. You can create worktrees for multiple repos if the task spans them.

## Rules

- Do NOT edit files under \`$WORKSPACE/repos/\` — a hook will block you.
- Do NOT create worktrees upfront. Only when you first need to write to a repo.
CLAUDEMD

# 4. Write prompt file if provided
if [ -n "$PROMPT" ]; then
  printf '%s\n' "$PROMPT" > "$TASK_DIR/prompt.md"
fi

# 5. Pre-trust the task dir so Claude honors .claude/settings.local.json.
#    Claude ignores permissions.allow entries from untrusted directories, and a
#    non-interactively launched task never gets the trust dialog accepted.
CLAUDE_JSON="$HOME/.claude.json"
if command -v jq >/dev/null 2>&1 && [ -f "$CLAUDE_JSON" ]; then
  tmp=$(mktemp)
  if jq --arg dir "$TASK_DIR" '.projects[$dir].hasTrustDialogAccepted = true' "$CLAUDE_JSON" > "$tmp"; then
    mv "$tmp" "$CLAUDE_JSON"
  else
    rm -f "$tmp"
    echo "WARNING: could not pre-trust $TASK_DIR in $CLAUDE_JSON" >&2
  fi
fi

# 6. Launch in tmux or print instructions
if [ -n "${TMUX:-}" ]; then
  tmux new-window -d -n "$TASK_NAME" -c "$TASK_DIR"
  tmux set-window-option -t "$TASK_NAME" automatic-rename off
  if [ -n "$PROMPT" ]; then
    tmux send-keys -t "$TASK_NAME" 'claude "$(cat prompt.md)"' Enter
  else
    tmux send-keys -t "$TASK_NAME" 'claude' Enter
  fi
  echo "Launched in background tmux window: $TASK_NAME"
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
