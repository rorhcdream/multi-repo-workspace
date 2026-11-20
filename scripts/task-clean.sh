#!/bin/bash
# Cleans up a completed task: removes worktrees, closes the tmux window, deletes
# the task directory, deletes merged task branches, and prunes stale worktree refs.
#
# Safety:
#   - Aborts if any worktree has uncommitted changes, unless --force is passed.
#   - Only deletes branches confirmed landed on origin's refreshed default. Unmerged
#     branches are kept and reported; delete them yourself with -D if intended.
#
# Usage: task-clean.sh <workspace> <task-name> [--force]
set -uo pipefail

WORKSPACE="$1"
TASK_NAME="$2"
FORCE="${3:-}"
TASK_DIR="$WORKSPACE/tasks/$TASK_NAME"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

# Disposable tmp directories and runtime/noise files that must not count as uncommitted
# work — otherwise they'd trigger the abort below and force an unnecessary
# confirmation. Matched at any depth. Override with TASK_CLEAN_IGNORE
# (space-separated basenames/globs).
read -ra _ignore_globs <<< "${TASK_CLEAN_IGNORE:-nohup.out *.log tmp/}"
ignore_pathspec=()
for g in "${_ignore_globs[@]}"; do
  if [ "$g" = "tmp/" ]; then
    ignore_pathspec+=(":(glob,exclude)**/tmp/**")
  else
    ignore_pathspec+=(":(exclude)*$g")
  fi
done

if [ ! -d "$TASK_DIR" ]; then
  echo "No task directory at $TASK_DIR" >&2
  exit 1
fi

# Worktrees are usually <task>/<repo>, but can be nested (e.g. <task>/rollback/<repo>),
# so find them at any depth instead of globbing one level. -prune stops the descent
# once a worktree is found, so nothing inside one is taken for a separate worktree.
find_worktrees() {
  find "$TASK_DIR" -mindepth 1 -type d -exec test -e '{}/.git' \; -print -prune
}

# 1. Pre-flight: check for uncommitted changes in any worktree (ignoring noise).
dirty=""
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  case "/${dir#"$TASK_DIR"/}/" in
    */tmp/*) continue ;;
  esac
  status=$(git -C "$dir" status --porcelain -- . "${ignore_pathspec[@]}")
  if [ -n "$status" ]; then
    dirty="$dirty\n=== ${dir#$TASK_DIR/} ===\n$status"
  fi
done < <(find_worktrees)

if [ -n "$dirty" ] && [ "$FORCE" != "--force" ]; then
  echo "Uncommitted changes found — aborting. Re-run with --force to clean anyway:" >&2
  printf '%b\n' "$dirty" >&2
  exit 2
fi

# 2. Gather worktrees to remove and every task branch to clean up.
#    Each worktree gives its checked-out tip branch; a stacked-PR task also has
#    extra branches in the same repo (under refs/heads/<task-name>/) that no
#    worktree has checked out. Collect both, deduped.
declare -a dirs=()          # worktree paths to remove
declare -a wt_src_repos=()  # source repo per worktree (parallel to dirs)
declare -a del_branches=()  # every task branch to consider deleting
declare -a del_src_repos=() # source repo per branch (parallel to del_branches)
seen=""                     # newline-delimited "<repo>|<branch>" set for dedupe
                            # ponytail: breaks only if a repo path contains '|'

add_branch() {  # $1=src_repo  $2=branch
  local key
  key=$'\n'"$1|$2"$'\n'
  case "$seen" in *"$key"*) return ;; esac
  seen="$seen$key"
  del_branches+=("$2")
  del_src_repos+=("$1")
}

while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || continue
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
  src_repo=$(dirname "$common")
  dirs+=("${dir%/}")
  wt_src_repos+=("$src_repo")
  # A detached HEAD reports the literal "HEAD", which is not a branch.
  [ "$branch" = HEAD ] || add_branch "$src_repo" "$branch"
  # Whole stack: every branch under the task-name prefix in this repo. The
  # pattern has no wildcard on purpose — for-each-ref treats it as a literal
  # prefix and matches nested refs, whereas fnmatch's '*' won't cross a '/'
  # and would miss <task>/rollback/<branch>.
  while IFS= read -r b; do
    [ -n "$b" ] && add_branch "$src_repo" "$b"
  done < <(git -C "$src_repo" for-each-ref --format='%(refname:short)' "refs/heads/$TASK_NAME/" 2>/dev/null)
done < <(find_worktrees)

# 3. Remove each worktree. Run from the source repo (-C "$src"); this script's
#    cwd is the task dir, which is not a git repo, so a bare `git worktree remove`
#    would fail with "fatal: not a git repository".
for i in "${!dirs[@]}"; do
  dir="${dirs[$i]}"
  src="${wt_src_repos[$i]}"
  if git -C "$src" worktree remove "$dir" 2>/dev/null \
     || git -C "$src" worktree remove --force "$dir"; then
    echo "Removed worktree: ${dir#$TASK_DIR/}"
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

# 6. Delete landed task branches; keep (and report) the rest.
deleted=""
kept=""
for i in "${!del_branches[@]}"; do
  branch="${del_branches[$i]}"
  src_repo="${del_src_repos[$i]}"

  state=$(bash "$SCRIPT_DIR/task-branch-status.sh" "$src_repo" "$branch")
  if [[ "$state" = LANDED:* ]] && git -C "$src_repo" branch -D "$branch" >/dev/null 2>&1; then
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
echo "Deleted branches (landed on origin default):${deleted:- none}"
echo "Kept branches (check integration status before deleting):${kept:- none}"
