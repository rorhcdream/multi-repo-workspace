#!/bin/bash
# Creates a task directory with all necessary config and launches the selected
# agent in tmux — directly by default, or inside Neovim (sidecar.nvim) with --nvim.
# Usage: task-setup.sh [--agent claude|codex] [--nvim|--no-nvim] <workspace> <task-name> [prompt-text] [additional-context]
#
# Defaults come from the environment, so a machine can opt in once instead of
# passing a flag every time. Flags always win over the environment:
#   MRW_AGENT=claude|codex   default agent
#   MRW_NVIM=1               launch inside Neovim (sidecar.nvim) by default
#   MRW_TASK_INSTRUCTIONS_FILE=/path/to/file
#                            append personal instructions to the task doc
set -euo pipefail

AGENT="${MRW_AGENT:-claude}"
case "${MRW_NVIM:-0}" in
  1|true|yes|on) USE_NVIM=1 ;;
  *)             USE_NVIM=0 ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --agent)    AGENT="${2:-}"; shift 2 ;;
    --claude)   AGENT="claude"; shift ;;
    --codex)    AGENT="codex"; shift ;;
    --nvim)     USE_NVIM=1; shift ;;
    --no-nvim)  USE_NVIM=0; shift ;;
    *) break ;;
  esac
done
case "$AGENT" in
  claude|codex) ;;
  *) echo "ERROR: unknown agent '$AGENT' (expected claude or codex)" >&2; exit 1 ;;
esac

WORKSPACE="$1"
TASK_NAME="$2"
PROMPT="${3:-}"
ADDITIONAL_CONTEXT="${4:-}"
TASK_DIR="$WORKSPACE/tasks/$TASK_NAME"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CUSTOM_INSTRUCTIONS_FILE="${MRW_TASK_INSTRUCTIONS_FILE:-}"
CUSTOM_INSTRUCTIONS_SNAPSHOT=""

cleanup() {
  if [ -n "$CUSTOM_INSTRUCTIONS_SNAPSHOT" ]; then
    rm -f "$CUSTOM_INSTRUCTIONS_SNAPSHOT"
  fi
}
trap cleanup EXIT

if [ -n "$CUSTOM_INSTRUCTIONS_FILE" ]; then
  case "$CUSTOM_INSTRUCTIONS_FILE" in
    /*) ;;
    *) CUSTOM_INSTRUCTIONS_FILE="$PWD/$CUSTOM_INSTRUCTIONS_FILE" ;;
  esac
  if [ ! -f "$CUSTOM_INSTRUCTIONS_FILE" ] || [ ! -r "$CUSTOM_INSTRUCTIONS_FILE" ]; then
    echo "ERROR: MRW_TASK_INSTRUCTIONS_FILE is not a readable file" >&2
    exit 1
  fi
  CUSTOM_INSTRUCTIONS_SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/mrw-task-instructions.XXXXXX")"
  cp "$CUSTOM_INSTRUCTIONS_FILE" "$CUSTOM_INSTRUCTIONS_SNAPSHOT"
fi

# 1. Create directory structure
mkdir -p "$TASK_DIR"

# 2. Agent-specific sandbox config + escalation wording.
#    Both agents keep repos/ read-only; only the mechanism differs.
#    - claude: Bash sandbox (allowWrite excludes repos/ source files) + a
#      PreToolUse hook that blocks Edit/Write to repos/. Escalate per-command
#      with `dangerouslyDisableSandbox: true`.
#    - codex: `--sandbox workspace-write` makes the task dir (cwd) writable and
#      everything outside it (including repos/) read-only. Escalate by asking
#      for approval to run with full access.
if [ "$AGENT" = "claude" ]; then
  mkdir -p "$TASK_DIR/.claude"
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
  ESCALATE="**Run with \`dangerouslyDisableSandbox: true\`** (needs network)"
  READONLY_NOTE="a hook will block you"
  DOC_FILE="CLAUDE.md"
else
  ESCALATE="**Run it with escalated permissions** (it needs network and write access outside the \`workspace-write\` sandbox — approve the escalation when asked)"
  READONLY_NOTE="the \`workspace-write\` sandbox makes them read-only"
  DOC_FILE="AGENTS.md"
fi

# 3. Write the agent instructions doc (CLAUDE.md or AGENTS.md).
cat > "$TASK_DIR/$DOC_FILE" <<CLAUDEMD
# Task: $TASK_NAME

## Workspace layout

- \`$WORKSPACE/repos/\` — Source repos. **Read-only.** Browse freely for context.
- \`./\<repo\>/\` — Git worktrees you create for this task. Edit files here.

## Workflow

1. Before reading a repo for context, update it to the latest default branch — but only the repos you'll actually read. $ESCALATE:
   \`\`\`bash
   $SCRIPT_DIR/repos-update.sh "$WORKSPACE" <repo> [<repo> ...]
   \`\`\`
2. Read across \`$WORKSPACE/repos/\` to understand the problem.
3. When you need to modify a repo, create a worktree using the helper script. $ESCALATE — it fetches from the remote and writes to the source repo's \`.git/\` directory.
   \`\`\`bash
   $SCRIPT_DIR/worktree-add.sh "$WORKSPACE" "$TASK_NAME" <category> <repo> <branch-desc>
   \`\`\`
   The script fetches origin's default branch first, then creates the worktree branched from \`origin/<default>\` so you always start from the latest \`main\`/\`master\`.
4. Edit files under \`./\<repo\>/\`, never under \`$WORKSPACE/repos/\`.
5. You can create worktrees for multiple repos if the task spans them.

## Rules

- Do NOT edit files under \`$WORKSPACE/repos/\` — $READONLY_NOTE.
- Do NOT create worktrees upfront. Only when you first need to write to a repo.
CLAUDEMD

if [ -n "$CUSTOM_INSTRUCTIONS_SNAPSHOT" ]; then
  printf '\n' >> "$TASK_DIR/$DOC_FILE"
  cat "$CUSTOM_INSTRUCTIONS_SNAPSHOT" >> "$TASK_DIR/$DOC_FILE"
  printf '\n' >> "$TASK_DIR/$DOC_FILE"
fi

# 4. Write the original prompt verbatim. Keep optional context separate on disk,
#    but include it in the initial message sent to the new agent.
#    TASK_PROMPT_FILE stays empty when there is nothing to send at launch.
TASK_PROMPT_FILE=""
if [ -n "$PROMPT" ]; then
  printf '%s\n' "$PROMPT" > "$TASK_DIR/prompt.md"
  TASK_PROMPT_FILE="prompt.md"
fi
if [ -n "$ADDITIONAL_CONTEXT" ]; then
  printf '%s\n' "$ADDITIONAL_CONTEXT" > "$TASK_DIR/context.md"
  {
    if [ -n "$PROMPT" ]; then
      printf '%s\n\n' "$PROMPT"
      printf 'Additional context (background information; the task prompt above remains authoritative):\n'
    else
      printf 'Additional context (background information):\n'
    fi
    printf '%s\n' "$ADDITIONAL_CONTEXT"
  } > "$TASK_DIR/task-input.md"
  TASK_PROMPT_FILE="task-input.md"
fi

# 5. Pre-trust the task dir so the agent honors its config without an
#    interactive trust dialog (a non-interactively launched task never gets to
#    accept one).
if [ "$AGENT" = "claude" ]; then
  # Claude ignores permissions.allow entries from untrusted directories.
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
else
  # Codex records folder trust as [projects."<path>"] trust_level = "trusted"
  # in ~/.codex/config.toml. Append the entry if it isn't already there.
  CODEX_CONFIG="$HOME/.codex/config.toml"
  mkdir -p "$HOME/.codex"
  touch "$CODEX_CONFIG"
  if ! grep -qF "[projects.\"$TASK_DIR\"]" "$CODEX_CONFIG"; then
    printf '\n[projects."%s"]\ntrust_level = "trusted"\n' "$TASK_DIR" >> "$CODEX_CONFIG"
  fi
fi

# 6. Build the launch command: the agent directly (default), or inside Neovim
#    via sidecar.nvim when --nvim is passed. Direct codex launches pass
#    --sandbox workspace-write explicitly; under --nvim, sidecar's codex tool
#    config must include the same flag to keep repos/ read-only.
if [ "$USE_NVIM" = 1 ]; then
  RUN="nvim -c 'Sidecar $AGENT'"
  if [ -n "$TASK_PROMPT_FILE" ]; then
    # Let the selected agent initialize before asking Sidecar to submit the
    # generated prompt. vim.defer_fn is non-blocking, so Neovim can finish
    # startup while the two-second delay elapses.
    RUN="$RUN -c \"lua vim.defer_fn(function() vim.cmd('SidecarPromptFile! $TASK_PROMPT_FILE') end, 2000)\""
  fi
  LAUNCHED="Neovim with $AGENT"
else
  if [ "$AGENT" = "claude" ]; then
    RUN="claude"
  else
    RUN="codex --sandbox workspace-write"
  fi
  if [ -n "$TASK_PROMPT_FILE" ]; then
    RUN="$RUN \"\$(cat $TASK_PROMPT_FILE)\""
  fi
  LAUNCHED="$AGENT"
fi

if [ -n "${TMUX:-}" ]; then
  tmux new-window -d -n "$TASK_NAME" -c "$TASK_DIR"
  tmux set-window-option -t "$TASK_NAME" automatic-rename off
  tmux send-keys -t "$TASK_NAME" "$RUN" Enter
  echo "Launched $LAUNCHED in background tmux window: $TASK_NAME"
else
  echo "Task directory created: $TASK_DIR"
  echo "Run:"
  echo "  cd $TASK_DIR"
  echo "  $RUN"
fi
