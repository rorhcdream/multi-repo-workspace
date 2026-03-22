#!/bin/bash
# Deterministic hook: blocks Edit/Write to files under repos/
# The sandbox only applies to Bash subprocesses, not Edit/Write tools.
# This hook is the sole enforcement for Edit/Write — the sandbox handles Bash.

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')

case "$tool_name" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

file_path=$(echo "$input" | jq -r '.tool_input.file_path')

# Resolve to absolute path, following symlinks
case "$file_path" in
  /*) abs_path="$file_path" ;;
  *)  abs_path="$PWD/$file_path" ;;
esac
if command -v realpath >/dev/null 2>&1; then
  abs_path=$(realpath -m "$abs_path" 2>/dev/null || echo "$abs_path")
fi

# Find workspace root by walking up for .workspace marker
dir="$PWD"
ws_root=""
while [ "$dir" != "/" ]; do
  if [ -f "$dir/.workspace" ]; then
    ws_root="$dir"
    break
  fi
  dir=$(dirname "$dir")
done

# Not in a workspace — allow
[ -z "$ws_root" ] && exit 0

repos_dir="$ws_root/repos"

case "$abs_path" in
  "$repos_dir"/*)
    rel="${abs_path#$repos_dir/}"
    category=$(echo "$rel" | cut -d/ -f1)
    repo=$(echo "$rel" | cut -d/ -f2)

    cat <<HOOK_EOF
{"decision":"block","reason":"Cannot write to repos/ — it is read-only. You need to create a task worktree first.\n\n1. If no task is active, ask the user to start one or create a task directory:\n   mkdir -p $ws_root/tasks/<task-name>\n\n2. Create a worktree for this repo:\n   git -C $repos_dir/$category/$repo worktree add $ws_root/tasks/<task-name>/$repo -b <branch-name>\n\n3. Then edit the file at the equivalent path under tasks/<task-name>/$repo/ instead."}
HOOK_EOF
    ;;
esac

exit 0
