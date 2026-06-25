#!/bin/bash
# Cleans up a completed task: removes worktrees, closes the tmux window, deletes
# the task directory, deletes merged task branches, and prunes stale worktree refs.
#
# Safety:
#   - Aborts if any worktree has uncommitted changes, unless --force is passed.
#   - Only deletes branches that are already merged (git branch -d). Unmerged
#     branches are kept and reported; delete them yourself with -D if intended.
#
# Usage: task-clean.sh <workspace> <task-name> [--force]
set -uo pipefail

WORKSPACE="$1"
TASK_NAME="$2"
FORCE="${3:-}"
TASK_DIR="$WORKSPACE/tasks/$TASK_NAME"

if [ ! -d "$TASK_DIR" ]; then
  echo "No task directory at $TASK_DIR" >&2
  exit 1
fi

# 1. Pre-flight: check for uncommitted changes in any worktree.
dirty=""
for dir in "$TASK_DIR"/*/; do
  [ -e "$dir/.git" ] || continue
  if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    dirty="$dirty\n=== $(basename "$dir") ===\n$(git -C "$dir" status --short)"
  fi
done

if [ -n "$dirty" ] && [ "$FORCE" != "--force" ]; then
  echo "Uncommitted changes found — aborting. Re-run with --force to clean anyway:" >&2
  printf '%b\n' "$dirty" >&2
  exit 2
fi

# 2. Record worktree dir + branch + source-repo for each worktree before removing it.
declare -a dirs=()
declare -a branches=()
declare -a src_repos=()
for dir in "$TASK_DIR"/*/; do
  [ -e "$dir/.git" ] || continue
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || continue
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
  src_repo=$(dirname "$common")
  dirs+=("${dir%/}")
  branches+=("$branch")
  src_repos+=("$src_repo")
done

# 3. Remove each worktree. Run from the source repo (-C "$src"); this script's
#    cwd is the task dir, which is not a git repo, so a bare `git worktree remove`
#    would fail with "fatal: not a git repository".
for i in "${!branches[@]}"; do
  dir="${dirs[$i]}"
  src="${src_repos[$i]}"
  if git -C "$src" worktree remove "$dir" 2>/dev/null \
     || git -C "$src" worktree remove --force "$dir"; then
    echo "Removed worktree: $(basename "$dir")"
  else
    echo "WARNING: could not remove worktree $dir (will rm + prune)" >&2
  fi
done

# 4. Close the tmux window for this task (if inside tmux).
if [ -n "${TMUX:-}" ]; then
  tmux kill-window -t "$TASK_NAME" 2>/dev/null || true
fi

# 5. Remove the task directory.
rm -rf "$TASK_DIR"
echo "Removed task directory: $TASK_DIR"

# 6. Delete merged task branches; keep (and report) the rest.
#    git branch -d only catches fast-forward / merge-commit merges. Squash and
#    rebase merges are not visible in local history — those are resolved by the
#    caller via PR status (see the task-clean skill).
deleted=""
kept=""
for i in "${!branches[@]}"; do
  branch="${branches[$i]}"
  src_repo="${src_repos[$i]}"

  if git -C "$src_repo" branch -d "$branch" >/dev/null 2>&1; then
    deleted="$deleted $branch"
  else
    kept="$kept $branch"
  fi
done

# 7. Prune stale worktree refs across all source repos.
for repo in "$WORKSPACE"/repos/*/*/; do
  [ -e "$repo/.git" ] || continue
  git -C "$repo" worktree prune 2>/dev/null || true
done

# 8. Report.
echo "---"
echo "Deleted branches (merged in local history):${deleted:- none}"
echo "Kept branches (check PR status, then delete with -D if merged):${kept:- none}"
