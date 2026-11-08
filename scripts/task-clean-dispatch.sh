#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: task-clean-dispatch.sh <workspace> <task-name>" >&2
  exit 1
fi

WORKSPACE="$(cd "$1" && pwd -P)"
TASK_NAME="$2"

case "$TASK_NAME" in
  ''|.|..|*/*|*$'\n'*|*$'\r'*) echo "ERROR: expected a single task directory name" >&2; exit 1 ;;
esac
if [ ! -f "$WORKSPACE/.workspace" ] || [ ! -d "$WORKSPACE/tasks/$TASK_NAME" ]; then
  echo "ERROR: workspace marker or task directory not found" >&2
  exit 1
fi
if [ -z "${TMUX:-}" ]; then
  echo "ERROR: task-local cleanup delegation requires tmux; invoke task-clean from a separate workspace-root session" >&2
  exit 1
fi

pane_agent() {
  local pane="$1" current pane_pid
  current=$(tmux display-message -p -t "$pane" '#{pane_current_command}')
  case "${current##*/}" in
    codex*) printf codex; return ;;
    claude*) printf claude; return ;;
  esac
  pane_pid=$(tmux display-message -p -t "$pane" '#{pane_pid}')
  ps -Ao pid=,ppid=,comm=,args= | awk -v root="$pane_pid" '
    function depth(pid, cur, count) {
      cur=pid
      for(count=0; count<100 && cur; count++) {
        if(cur==root) return count
        cur=parent[cur]
      }
      return -1
    }
    function kind(name, args, fields, count, field_index, base, seen) {
      if(name ~ /\/claude\/versions\//) return "claude"
      base=name; sub(/^.*\//, "", base)
      if(base ~ /^codex([.]|$)/) return "codex"
      if(base ~ /^claude([.]|$)/) return "claude"
      count=split(args, fields, /[[:space:]]+/)
      for(field_index=1; field_index<=count && seen<2; field_index++) {
        if(fields[field_index]=="") continue
        seen++
        base=fields[field_index]; sub(/^.*\//, "", base)
        if(base ~ /^codex([.]|$)/) return "codex"
        if(base ~ /^claude([.]|$)/) return "claude"
      }
      return ""
    }
    {
      pid=$1; parent[pid]=$2; name[pid]=$3
      $1=$2=$3=""; command[pid]=$0
    }
    END {
      best=101; found=""
      for(pid in parent) {
        distance=depth(pid)
        if(distance<0 || distance>=best) continue
        agent=kind(name[pid], command[pid])
        if(agent!="") { best=distance; found=agent }
      }
      printf "%s", found
    }'
}

TARGET=""
AGENT=""
while IFS=$'\t' read -r pane_path pane_id; do
  [ -n "$pane_path" ] && [ -n "$pane_id" ] || continue
  physical_path=$(cd "$pane_path" 2>/dev/null && pwd -P) || continue
  [ "$physical_path" = "$WORKSPACE" ] || continue
  [ "$pane_id" != "${TMUX_PANE:-}" ] || continue
  agent=$(pane_agent "$pane_id") || continue
  case "$agent" in
    claude|codex) TARGET="$pane_id"; AGENT="$agent"; break ;;
  esac
done < <(tmux list-panes -s -F $'#{pane_current_path}\t#{pane_id}')

if [ -z "$TARGET" ]; then
  echo "ERROR: no existing Claude or Codex pane at the workspace root in this tmux session; start a root agent and retry" >&2
  exit 1
fi

case "$AGENT" in
  codex) PREFIX='$task-clean' ;;
  claude) PREFIX='/task-clean' ;;
esac
if [ "$(tmux display-message -p -t "$TARGET" '#{pane_in_mode}')" = 1 ]; then
  tmux send-keys -t "$TARGET" -X cancel
fi
tmux send-keys -t "$TARGET" -l -- "$PREFIX $TASK_NAME"
sleep 0.1
tmux send-keys -t "$TARGET" Enter
printf 'Cleanup request sent to existing workspace-root %s pane %s. Completion and blockers will appear there; focus is unchanged.\n' "$AGENT" "$TARGET"
