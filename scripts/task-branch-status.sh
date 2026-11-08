#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: task-branch-status.sh <repo> <branch>" >&2
  exit 1
fi

REPO="$1"
BRANCH="$2"
if ! TIP=$(git -C "$REPO" rev-parse --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null); then
  echo "UNKNOWN: local branch not found"
  exit 0
fi
if ! REMOTE_HEAD=$(git -C "$REPO" ls-remote --symref origin HEAD 2>/dev/null); then
  echo "UNKNOWN: cannot resolve origin default branch"
  exit 0
fi
DEFAULT_REF=$(printf '%s\n' "$REMOTE_HEAD" | awk '$1=="ref:" && $3=="HEAD" {print $2; exit}')
case "$DEFAULT_REF" in
  refs/heads/*) DEFAULT="${DEFAULT_REF#refs/heads/}" ;;
  *) echo "UNKNOWN: origin default branch is not advertised"; exit 0 ;;
esac
if ! git -C "$REPO" fetch --quiet origin "+$DEFAULT_REF:refs/remotes/origin/$DEFAULT" 2>/dev/null; then
  echo "UNKNOWN: cannot refresh origin default branch"
  exit 0
fi
if [ "$BRANCH" = "$DEFAULT" ]; then
  echo "DEFAULT: $BRANCH (never delete)"
elif git -C "$REPO" merge-base --is-ancestor "$TIP" "refs/remotes/origin/$DEFAULT"; then
  echo "LANDED: origin/$DEFAULT"
else
  echo "UNCONFIRMED: origin/$DEFAULT (check PR state or retain branch)"
fi
