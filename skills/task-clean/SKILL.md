---
name: task-clean
description: Clean up completed task worktrees and directories through a background worker. Use when the user asks to "clean up a task", "remove task", "finish task", or "delete worktrees". Accepts a task name, a tmux window number, or a natural language description.
allowed-tools: Bash, Read, Glob, Grep, Agent
---

Clean up a completed task in the multi-repo workspace.

Task to clean: $ARGUMENTS

> **Codex compatibility**: `${CLAUDE_PLUGIN_ROOT}` is Claude Code's plugin-root variable — under Codex, substitute this plugin's root directory (two levels above this SKILL.md). Steps that say to run with `dangerouslyDisableSandbox: true` mean, under Codex, running the command with escalated permissions (approve the sandbox escalation).

## Background dispatch

Unless the invocation identifies you as the **task-clean background worker**, do not execute the cleanup steps in the foreground.

1. Launch exactly one general-purpose subagent in the background. Under Claude Code, use the `Agent` tool with `run_in_background: true`. Under Codex, use the available subagent spawning capability and leave it running without waiting or polling.
2. Give it the original `$ARGUMENTS`, the current working directory, and this instruction: `You are the task-clean background worker. Execute the task-clean skill steps directly. Do not delegate or spawn another worker. Never force cleanup without explicit user confirmation. Report completion or a blocker when finished.`
3. Tell the user that cleanup was dispatched, then end the foreground turn immediately so another command can be issued.

If background subagents are unavailable, report that limitation and stop. Do not silently run the workflow in the foreground.

If you are the marked task-clean background worker, skip this section and execute the steps below directly. If cleanup requires confirmation, stop before mutation and report the exact blocker to the user; do not wait indefinitely or infer approval.

## Steps

1. **Find workspace root** by locating the `.workspace` marker.

2. **Identify the task.**
   - If `$ARGUMENTS` is a plain integer (e.g. `3`), treat it as a tmux window number and resolve the task name from the window name:
     ```bash
     task_name=$(tmux display-message -p -t <number> '#W')
     ```
     Verify that `<workspace>/tasks/$task_name/` exists. If not, fall back to listing and asking.
   - If `$ARGUMENTS` is a task name or description, use it directly.
   - If `$ARGUMENTS` is empty and the current working directory is inside `<workspace>/tasks/<task-name>/`, use that task name. Before cleanup, `cd <workspace>` so subsequent commands don't run inside the soon-to-be-deleted directory.
   - If `$ARGUMENTS` is empty and not in a task directory, list active tasks and ask the user:
     ```bash
     ls <workspace>/tasks/
     ```

3. **Check for uncommitted changes** in each worktree before removing. Ignore generated PR drafts (`tmp/pr-draft.md`, `tmp/pr-stack-*.md`) and runtime noise (`nohup.out`, `*.log`) so they don't trigger a needless prompt — mirror the cleanup script, which excludes the same paths. Do not ignore the entire `tmp/` directory; other files there may be real work:
   ```bash
   while IFS= read -r dir; do
     [ -n "$dir" ] || continue
     echo "=== ${dir#*/tasks/<task-name>/} ==="
     git -C "$dir" status --short -- . \
       ':(exclude)*nohup.out' \
       ':(exclude)*.log' \
       ':(exclude)*tmp/pr-draft.md' \
       ':(exclude)*tmp/pr-stack-*.md'
   done < <(
     find "<workspace>/tasks/<task-name>" -mindepth 1 -type d \
       -exec test -e '{}/.git' \; -print -prune
   )
   ```
   Delete the generated PR drafts with the task without asking about them. If there are other uncommitted changes, warn the user and ask for confirmation before proceeding. Pass `--force` to the cleanup script (step 5) only after the user confirms. (`TASK_CLEAN_IGNORE` — space-separated basenames/globs — widens what counts as disposable noise, but it is only for genuine generated or runtime files. Using it to slip a real change past the abort gate is `--force` by another name and needs the same explicit confirmation.)

4. **Assess each branch's merge status — before running the cleanup script.** GitHub's PR merge state is the authoritative signal (it knows about squash *and* rebase merges, which local history can't show). Query it so you have the branch→repo mapping and a full picture up front. Enumerate **all** task branches per repo (`refs/heads/<task-name>/`), not just each worktree's tip — a stacked-PR task has multiple branches in one repo and only the tip is checked out. The ref pattern deliberately has no trailing `*`: `for-each-ref` treats a wildcard-free pattern as a literal prefix and matches nested refs, whereas fnmatch's `*` will not cross a `/` and silently misses a branch like `<task-name>/rollback/<branch>`:
   ```bash
   while IFS= read -r dir; do
     [ -n "$dir" ] || continue
     repo=$(dirname "$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)")
     origin=$(git -C "$repo" remote get-url origin)
     for branch in $(git -C "$repo" for-each-ref --format='%(refname:short)' "refs/heads/<task-name>/"); do
       echo "=== $(basename "$repo") | $branch ==="
       gh -R "$origin" pr list --head "$branch" --state all --json number,state,mergedAt,title
     done
   done < <(
     find "<workspace>/tasks/<task-name>" -mindepth 1 -type d \
       -exec test -e '{}/.git' \; -print -prune
   )
   ```
   (`gh -R` accepts the origin URL directly, so there's no need to parse out `owner/repo`.) Classify each branch:
   - `"state": "MERGED"` (non-null `mergedAt`) → **fully merged; safe to delete in step 6.** A merged PR contains *every* commit on the branch. A squash merge collapses them into one commit titled with the PR, so the branch's individual commit subjects will be absent from the default branch and `git log <default>..<branch>` will still show commits "ahead" — this is normal and does **not** mean a commit was unpushed or lost. Trust the PR state.
   - `OPEN`, or no PR → keep; do not delete.
   - `gh` unavailable, repo not on GitHub, or the user says it was merged elsewhere → fall back to trusting the user after confirming. Don't insist a branch is unmerged just because `git branch -d` later fails.

5. **Run the cleanup script.** It removes worktrees, closes the tmux window, deletes the task directory, prunes stale worktree refs, and deletes branches it can confirm merged from local history — all in one step. **Run with `dangerouslyDisableSandbox: true`** — it writes to the source repos' `.git/` directories and kills the tmux window, which the sandbox blocks.
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task-clean.sh "<workspace>" "<task-name>" [--force]
   ```
   - Aborts if any worktree has uncommitted changes other than the generated PR drafts and runtime noise listed in step 3, unless `--force` is passed — so the step 3 check is your safety gate.
   - It discovers every task branch per repo via the `refs/heads/<task-name>/` prefix (so the whole stack of a stacked-PR task is covered, not just each worktree's tip). Branches created inside a worktree with a name that doesn't follow the `<task-name>/` prefix are the exception — they can't be attributed to the task and won't be found; delete those by hand.
   - For branch deletion it only runs `git branch -d`, which catches fast-forward / merge-commit merges. It does **not** attempt to detect squash or rebase merges — those aren't visible in local history (a squash replaces the branch's commits with one new commit on the default branch, so the originals are never ancestors of origin). Any branch it can't confirm this way is reported as kept and resolved by PR status in step 6.

6. **Delete remaining merged branches.** For each branch you classified `MERGED` in step 4 that the script reports as kept (e.g. a rebase merge, or one the patch-id heuristic missed), delete it now that its worktree is gone:
   ```bash
   git -C <workspace>/repos/<category>/<repo> branch -D <branch>
   ```

7. **Report** what was cleaned up — the script's deleted/kept lists, any branches you deleted in step 6, and any kept because their PR is still open.
