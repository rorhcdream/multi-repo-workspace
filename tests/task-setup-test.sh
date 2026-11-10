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

# Context forwarding, exercised with stub tmux/claude so nothing really launches.
FAKE_BIN="$TEST_ROOT/bin"
TMUX_LOG="$TEST_ROOT/tmux.log"
TMUX_CMD="$TEST_ROOT/tmux.cmd"
AGENT_ARG="$TEST_ROOT/agent.arg"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/tmux" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$TMUX_LOG"
if [ "\$1" = send-keys ]; then printf '%s' "\$4" > "$TMUX_CMD"; fi
STUB
cat > "$FAKE_BIN/claude" <<STUB
#!/bin/bash
printf '%s' "\$1" > "$AGENT_ARG"
STUB
chmod +x "$FAKE_BIN/tmux" "$FAKE_BIN/claude"

setup_in_tmux() {
  rm -f "$TMUX_LOG" "$TMUX_CMD" "$AGENT_ARG"
  HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" TMUX=fake \
    "$SCRIPT_DIR/task-setup.sh" --claude "$@" >/dev/null
}

fail() {
  echo "$1" >&2
  exit 1
}

# Contains shell metacharacters on purpose: they must survive untouched.
TRICKY_PROMPT='Fix `foo` and $(touch pwned) "quoted" \ it'
TRICKY_CONTEXT=$'Line one with `cmd`\n$(touch pwned-too) and $HOME'
LABEL='Additional context (background information; the task prompt above remains authoritative):'

setup_in_tmux --no-nvim "$WORKSPACE" "context-task" "$TRICKY_PROMPT" "$TRICKY_CONTEXT"
TASK="$WORKSPACE/tasks/context-task"
cmp <(printf '%s\n' "$TRICKY_PROMPT") "$TASK/prompt.md" || fail "prompt.md is not verbatim"
cmp <(printf '%s\n' "$TRICKY_CONTEXT") "$TASK/context.md" || fail "context.md is not verbatim"
cmp <(printf '%s\n\n%s\n%s\n' "$TRICKY_PROMPT" "$LABEL" "$TRICKY_CONTEXT") "$TASK/task-input.md" \
  || fail "task-input.md has the wrong layout"
grep -qF 'cat task-input.md' "$TMUX_CMD" || fail "direct launch did not use task-input.md"

# Run the launch command as tmux would, and check what the agent receives.
(cd "$TASK" && PATH="$FAKE_BIN:$PATH" bash -c "$(cat "$TMUX_CMD")")
cmp <(printf '%s\n\n%s\n%s' "$TRICKY_PROMPT" "$LABEL" "$TRICKY_CONTEXT") "$AGENT_ARG" \
  || fail "agent did not receive the combined input"
if [ -e "$TASK/pwned" ] || [ -e "$TASK/pwned-too" ]; then
  fail "task input was evaluated by the shell"
fi

setup_in_tmux --nvim "$WORKSPACE" "context-nvim-task" "Prompt" "Context"
grep -qF 'SidecarPromptFile! task-input.md' "$TMUX_CMD" || fail "Neovim launch did not use task-input.md"

setup_in_tmux --no-nvim "$WORKSPACE" "plain-task" "Prompt only"
TASK="$WORKSPACE/tasks/plain-task"
grep -qF 'cat prompt.md' "$TMUX_CMD" || fail "no-context launch did not use prompt.md"
if [ -e "$TASK/context.md" ] || [ -e "$TASK/task-input.md" ]; then
  fail "context files were written without context"
fi

setup_in_tmux --nvim "$WORKSPACE" "plain-nvim-task" "Prompt only"
grep -qF 'SidecarPromptFile! prompt.md' "$TMUX_CMD" || fail "no-context Neovim launch did not use prompt.md"

# Context without a prompt must still launch, in both modes, without a label
# pointing at a task prompt that does not exist.
setup_in_tmux --no-nvim "$WORKSPACE" "context-only-task" "" "Only context"
TASK="$WORKSPACE/tasks/context-only-task"
grep -qF 'cat task-input.md' "$TMUX_CMD" || fail "context-only launch did not send task-input.md"
[ ! -e "$TASK/prompt.md" ] || fail "prompt.md was written without a prompt"
if grep -qF 'task prompt above' "$TASK/task-input.md"; then
  fail "context-only input refers to a missing prompt"
fi

setup_in_tmux --nvim "$WORKSPACE" "context-only-nvim-task" "" "Only context"
grep -qF 'SidecarPromptFile! task-input.md' "$TMUX_CMD" || fail "context-only Neovim launch sent no input"

setup_in_tmux --no-nvim "$WORKSPACE" "empty-task"
if grep -qF 'cat ' "$TMUX_CMD"; then
  fail "launch without prompt or context tried to read a prompt file"
fi

# With TMUX unset the script only prints the command, even if tmux is on PATH.
rm -f "$TMUX_LOG"
OUTPUT="$(HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" TMUX= \
  "$SCRIPT_DIR/task-setup.sh" --claude --no-nvim "$WORKSPACE" "no-tmux-task" "Prompt" "Context")"
[ ! -e "$TMUX_LOG" ] || fail "tmux was invoked with TMUX unset"
grep -qF 'cat task-input.md' <<<"$OUTPUT" || fail "printed command did not use task-input.md"

echo "task-setup tests passed"
