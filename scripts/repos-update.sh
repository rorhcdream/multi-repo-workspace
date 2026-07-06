#!/bin/bash
# Updates repos under <workspace>/repos/ to their default branches, in parallel.
# If the repo is on its default branch, pull --ff-only.
# Otherwise, fetch the default branch into the local default branch ref.
# Usage: repos-update.sh <workspace> [repo-name ...]
#   With no repo names, updates every repo. With names, updates only repos whose
#   directory basename matches (e.g. `repos-update.sh /ws service-a service-b`).
set -uo pipefail

WORKSPACE="$1"
shift
WANTED=("$@")
REPOS_DIR="$WORKSPACE/repos"

if [ ! -d "$REPOS_DIR" ]; then
  echo "No repos directory at $REPOS_DIR" >&2
  exit 1
fi

update_repo() {
  local repo="$1"
  local name category default current result
  name=$(basename "$repo")
  category=$(basename "$(dirname "$repo")")

  default=$(git -C "$repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  if [ -z "$default" ]; then
    git -C "$repo" remote set-head origin -a >/dev/null 2>&1
    default=$(git -C "$repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  fi

  if [ -z "$default" ]; then
    echo "=== $category/$name: no default branch, skip ==="
    return
  fi

  current=$(git -C "$repo" rev-parse --abbrev-ref HEAD)
  if [ "$current" = "$default" ]; then
    result=$(git -C "$repo" pull --ff-only origin "$default" 2>&1 | tail -1)
  else
    result=$(git -C "$repo" fetch origin "$default:$default" 2>&1 | tail -1)
  fi
  echo "=== $category/$name ($default): $result ==="
}

# Run each repo update in the background, capturing its output to a per-repo file
# so concurrent network output doesn't interleave. Print in order after all finish.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

wanted() {  # true if $1 is in WANTED, or WANTED is empty (= all)
  [ ${#WANTED[@]} -eq 0 ] && return 0
  local w
  for w in "${WANTED[@]}"; do [ "$w" = "$1" ] && return 0; done
  return 1
}

count=0
for repo in "$REPOS_DIR"/*/*/; do
  [ -d "$repo/.git" ] || [ -f "$repo/.git" ] || continue
  wanted "$(basename "$repo")" || continue
  count=$((count + 1))
  update_repo "$repo" >"$tmpdir/$count.out" 2>&1 &
done

if [ "$count" -eq 0 ]; then
  echo "No matching repos to update: ${WANTED[*]:-(none found under $REPOS_DIR)}" >&2
  exit 1
fi

wait

for n in $(seq 1 "$count"); do
  [ -f "$tmpdir/$n.out" ] && cat "$tmpdir/$n.out"
done
