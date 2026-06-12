#!/bin/bash
# Creates a git worktree for a task, branching from the latest default branch.
# Fetches origin first so the new branch is based on remote HEAD, not whatever
# happens to be checked out in the source repo.
#
# Usage: worktree-add.sh <workspace> <task-name> <category> <repo> <branch-desc>
set -euo pipefail

WORKSPACE="$1"
TASK_NAME="$2"
CATEGORY="$3"
REPO="$4"
BRANCH_DESC="$5"

SRC_REPO="$WORKSPACE/repos/$CATEGORY/$REPO"
WORKTREE_DIR="$WORKSPACE/tasks/$TASK_NAME/$REPO"
NEW_BRANCH="$TASK_NAME/$BRANCH_DESC"

# Resolve default branch from origin/HEAD; refresh if missing
default=$(git -C "$SRC_REPO" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
if [ -z "$default" ]; then
  git -C "$SRC_REPO" remote set-head origin -a >/dev/null
  default=$(git -C "$SRC_REPO" symbolic-ref refs/remotes/origin/HEAD | sed 's|refs/remotes/origin/||')
fi

# Fetch latest so origin/<default> is current
git -C "$SRC_REPO" fetch origin "$default"

# Create worktree branched from latest origin/<default>
git -C "$SRC_REPO" worktree add "$WORKTREE_DIR" -b "$NEW_BRANCH" "origin/$default"

echo "Created worktree: $WORKTREE_DIR"
echo "  Branch: $NEW_BRANCH"
echo "  Based on: origin/$default"
