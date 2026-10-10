#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

TEST_HOME="$TEST_ROOT/home"
WORKSPACE="$TEST_ROOT/workspace with spaces"
INSTRUCTIONS="$TEST_ROOT/custom instructions.md"
mkdir -p "$TEST_HOME" "$WORKSPACE/tasks"
printf '%s\n' '## Custom workflow' '' 'Follow the custom workflow.' > "$INSTRUCTIONS"

HOME="$TEST_HOME" \
TMUX= \
MRW_TASK_INSTRUCTIONS_FILE="$INSTRUCTIONS" \
  "$SCRIPT_DIR/task-setup.sh" --codex --no-nvim \
  "$WORKSPACE" "custom-task" "Test prompt" >/dev/null

TASK_DOC="$WORKSPACE/tasks/custom-task/AGENTS.md"
grep -qF '## Custom workflow' "$TASK_DOC"
grep -qF 'Follow the custom workflow.' "$TASK_DOC"
grep -qF 'Test prompt' "$WORKSPACE/tasks/custom-task/prompt.md"

ALIAS_TASK_DIR="$WORKSPACE/tasks/alias-task"
ALIAS_INSTRUCTIONS="$ALIAS_TASK_DIR/AGENTS.md"
mkdir -p "$ALIAS_TASK_DIR"
printf '%s\n' '## Existing custom workflow' > "$ALIAS_INSTRUCTIONS"

HOME="$TEST_HOME" \
TMUX= \
MRW_TASK_INSTRUCTIONS_FILE="$ALIAS_INSTRUCTIONS" \
  "$SCRIPT_DIR/task-setup.sh" --codex --no-nvim \
  "$WORKSPACE" "alias-task" "Alias test" >/dev/null

grep -qF '## Existing custom workflow' "$ALIAS_INSTRUCTIONS"

MISSING_WORKSPACE="$TEST_ROOT/missing-workspace"
if HOME="$TEST_HOME" \
  TMUX= \
  MRW_TASK_INSTRUCTIONS_FILE="$TEST_ROOT/does-not-exist.md" \
  "$SCRIPT_DIR/task-setup.sh" --codex --no-nvim \
  "$MISSING_WORKSPACE" "invalid-task" "Test prompt" >/dev/null 2>&1; then
  echo "expected an unreadable instruction file to fail" >&2
  exit 1
fi

if [ -e "$MISSING_WORKSPACE/tasks/invalid-task" ]; then
  echo "task directory was created before instruction-file validation" >&2
  exit 1
fi

echo "task-setup tests passed"
