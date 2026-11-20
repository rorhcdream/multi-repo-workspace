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

**When invoked inside a task, delegate outside that task's session first.** Locate the workspace root by walking ancestors for `.workspace`, and resolve the target task using step 2 below before dispatch (preserve the original working directory for implicit task selection). These bounded read-only lookups are allowed in the foreground. Do not perform cleanup safety checks or mutations yet.

If the original working directory is anywhere under `<workspace>/tasks/`, forward the request to the existing workspace-root agent, not a subagent owned by the task session:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-clean-dispatch.sh" "<workspace>" "<resolved-task-name>"
```

Run with escalated permissions as needed for tmux access. Like tmux-workspace-tree, the helper finds an existing pane at the workspace root, detects its agent, exits copy mode if needed, sends literal `$task-clean <name>` to Codex or `/task-clean <name>` to Claude, waits briefly, and submits Enter. It creates no window and does not switch focus. Unlike the tree's fallback window index, it requires a verified root pane and a recognized agent; it will not type into an unrelated shell. Tell the user the returned pane ID and that completion or blockers will appear in that root session, then end the turn without waiting. It cannot verify whether the agent already has unfinished input; if the user reports a pending question or draft there, stop and ask them to clear it rather than injecting another command. If no root agent is found, report the blocker and ask the user to start one or invoke cleanup there; do not create a new window or fall back to task-owned cleanup. Changing directory alone does not detach a worker from the task session that cleanup will close.

**When invoked outside a task**, use the existing background-subagent dispatch:

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
   - If `$ARGUMENTS` is empty and the original working directory is inside `<workspace>/tasks/<task-name>/`, use that task name. Resolve this before handing off to the workspace root and pass the explicit name to the root agent. Workers must run cleanup commands from `<workspace>`, never from the soon-to-be-deleted task directory.
   - If `$ARGUMENTS` is empty and not in a task directory, list active tasks and ask the user:
     ```bash
     ls <workspace>/tasks/
     ```

3. **Check for uncommitted changes** in each worktree before removing. All `tmp/` directories and their contents are disposable, at any depth in the task or its worktrees. Ignore them along with runtime noise (`nohup.out`, `*.log`) so they don't trigger a needless prompt — mirror the cleanup script, which excludes the same paths:
   ```bash
   while IFS= read -r dir; do
     [ -n "$dir" ] || continue
     case "/${dir#<workspace>/tasks/<task-name>/}/" in
       */tmp/*) continue ;;
     esac
     echo "=== ${dir#*/tasks/<task-name>/} ==="
     git -C "$dir" status --short -- . \
       ':(exclude)*nohup.out' \
       ':(exclude)*.log' \
       ':(glob,exclude)**/tmp/**'
   done < <(
     find "<workspace>/tasks/<task-name>" -mindepth 1 -type d \
       -exec test -e '{}/.git' \; -print -prune
   )
   ```
   Worktrees located inside a disposable `tmp/` directory are skipped by this uncommitted-change check; still assess their branches in step 4. Outside those directories, a worktree on a detached HEAD is also unsaved work if its commit is on no branch (`git -C "$dir" branch --contains HEAD` prints only `(no branch)`): removing the worktree drops that commit. Report such a commit and its SHA, and treat it like an uncommitted change that needs the user's confirmation.

   Delete all `tmp/` contents with the task without asking about them. If there are other uncommitted changes, warn the user and ask for confirmation before proceeding. Pass `--force` to the cleanup script (step 5) only after the user confirms. (`TASK_CLEAN_IGNORE` — space-separated basenames/globs — widens what counts as disposable noise, but additional exclusions are only for genuine generated or runtime files. Using it to slip a real change past the abort gate is `--force` by another name and needs the same explicit confirmation.)

   **Check standalone deliverables only when the task has no git worktree.** If the worktree discovery in step 3 finds any worktree, skip this check; keep the existing worktree checks unchanged. Otherwise, list the task contents and recursively identify files beyond the standard scaffolding:
   ```bash
   task_dir="<workspace>/tasks/<task-name>"
   ls -la "$task_dir"
   find "$task_dir" -mindepth 1 \
     \( \( -path "$task_dir/.claude" -o -type d -name tmp \) -prune \) -o \
     \( \( -type f -o -type l \) \
       ! -path "$task_dir/AGENTS.md" \
       ! -path "$task_dir/CLAUDE.md" \
       ! -path "$task_dir/prompt.md" \
       ! -path "$task_dir/context.md" \
       ! -path "$task_dir/task-input.md" \
       ! -path "$task_dir/plan.md" \
       ! -path "$task_dir/findings.md" \
       ! -path "$task_dir/.nvimlog" -print \)
   ```
   `scripts/task-setup.sh` is authoritative for generated scaffolding in both Claude and Codex modes: it creates `CLAUDE.md` or `AGENTS.md`, optional `prompt.md`, optional `context.md` and `task-input.md`, and Claude's `.claude/settings.local.json`; `.claude/` and Neovim's `.nvimlog` are standard scaffolding/runtime noise. The task-root `plan.md` and `findings.md` are disposable planning/investigation artifacts: delete them with the task without asking for confirmation. These exclusions apply only to `<task>/plan.md` and `<task>/findings.md`, not files with those names inside repositories or other subdirectories. If setup changes, verify any additional exclusions against that script rather than broadly ignoring file types or directories.

   Every `tmp/` directory is disposable: skip its contents and delete it with the task without asking for confirmation. This includes the task root, nested task directories, and repository worktrees.

   Report each non-scaffolding file's path and a brief content summary (e.g. the first few lines or its length) in the cleanup report before running step 5. Treat real deliverables like the uncommitted-change blocker in step 3: stop and request the user's go-ahead before deleting them. The dispatching prompt for this specific cleanup may explicitly account for trivial/empty content or content clearly already fully relayed in the conversation and allow cleanup; always perform the check and report what was found. This is a static filesystem check only; do not inspect live agent sessions or tmux pane contents.

4. **Assess each branch's integration status — before running the cleanup script.** Directly landed changes do not require a PR. Enumerate **all** task branches per repo (`refs/heads/<task-name>/`), as well as each worktree's checked-out branch. Record each branch's tip SHA for the final deletion check. The literal ref prefix has no wildcard so nested task branches are included:
   ```bash
   while IFS= read -r dir; do
     [ -n "$dir" ] || continue
     repo=$(dirname "$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)")
     while IFS= read -r branch; do
       echo "=== $(basename "$repo") | $branch ==="
       git -C "$repo" rev-parse "refs/heads/$branch"
       bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-branch-status.sh" "$repo" "$branch"
     done < <(
       git -C "$repo" for-each-ref --format='%(refname:short)' "refs/heads/<task-name>/"
       git -C "$dir" symbolic-ref --quiet --short HEAD
     )
   done < <(
     find "<workspace>/tasks/<task-name>" -mindepth 1 -type d \
       -exec test -e '{}/.git' \; -print -prune
   )
   ```
   The helper resolves origin's advertised default branch, fetches that branch without moving the local default, and checks ancestry. It needs network and source-repo `.git/` write access; escalate as needed. Deduplicate the branch→repo pairs above, then classify:
   - `LANDED` → the branch tip is already an ancestor of freshly fetched `origin/<default>`. Safe to delete after removing the worktree, even if there is no PR, the PR is still open, or `gh` is unavailable. This covers direct `land`, fast-forward, and merge-commit integration. Do not require a PR as a second gate.
   - `DEFAULT` → never delete the default branch.
   - `UNCONFIRMED` or `UNKNOWN` → check GitHub PR state when available:
     ```bash
     origin=$(git -C "<repo>" remote get-url origin)
     gh -R "$origin" pr list --head "<branch>" --state all --json number,state,mergedAt,title,headRefOid
     ```
     A `MERGED` PR with non-null `mergedAt` and `headRefOid` matching the recorded local branch tip confirms squash/rebase integration; classify it `PR_MERGED`. Do not delete new commits added after the PR merged, or rely on an old merged PR for a reused branch name.

     If the PR is `MERGED` but `headRefOid` differs from the local tip (the branch was rebased or amended after the PR head was recorded, and the PR head SHA is often not in the local clone), decide by content instead of stopping. Against the freshly fetched `origin/<default>` that the helper just updated, diff only the files the branch itself changed:
     ```bash
     base=$(git -C "<repo>" merge-base "<branch>" "origin/<default>")
     git -C "<repo>" diff --name-only -z "$base" "<branch>" \
       | xargs -0 git --literal-pathspecs -C "<repo>" diff --quiet "origin/<default>" "<branch>" --
     ```
     Exit status 0 means every changed file is identical on `<default>`, so the work landed: classify it `PR_MERGED`. A non-zero status means the branch holds content not on `<default>`: keep it as unconfirmed and report `git diff --stat "origin/<default>" "<branch>"` limited to those files. This applies only when a merged PR exists; with no PR, the next rule still holds.
   - No matching merged PR and no ancestry confirmation → retain the branch and report why. A branch pushed to its own upstream is not necessarily landed. For rebased/squashed work with no matching PR, ask the user to confirm integration; do not infer it from commit titles, an empty working tree, or an equal-looking diff. Unavailable network or `gh` is not by itself a reason to claim the work is unlanded or prevent removing a clean worktree while retaining its branch.

5. **Run the cleanup script.** It removes worktrees, closes the tmux window, deletes the task directory, prunes stale worktree refs, and deletes branches confirmed landed on origin's default branch — all in one step. **Run with `dangerouslyDisableSandbox: true`** — it needs network, writes to source repos' `.git/` directories, and kills the tmux window, which the sandbox blocks.
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task-clean.sh "<workspace>" "<task-name>" [--force]
   ```
   - Aborts if any worktree has uncommitted changes outside the disposable `tmp/` directories and runtime noise listed in step 3, unless `--force` is passed — so the step 3 check is your safety gate.
   - It discovers every task branch per repo via the `refs/heads/<task-name>/` prefix (so the whole stack of a stacked-PR task is covered, not just each worktree's tip). Branches created inside a worktree with a name that doesn't follow the `<task-name>/` prefix are the exception — they can't be attributed to the task and won't be found; delete those by hand.
   - Before branch deletion it runs `task-branch-status.sh` and deletes only `LANDED` branches, never `DEFAULT`, `UNCONFIRMED`, or `UNKNOWN` branches. It does not trust `git branch -d` alone, which can treat a pushed feature upstream as merged even when the default branch does not contain the work. Squash/rebase PR merges are resolved separately in step 6.

6. **Delete remaining confirmed integrated branches.** For each `LANDED` or `PR_MERGED` branch from step 4 that the script reports as kept, verify its tip still equals the recorded SHA, it is not the default branch, and no worktree still checks it out. Then delete it. If the tip changed, reassess instead of applying stale integration evidence. Retain unconfirmed branches unless the user explicitly authorized their deletion after integration was discussed:
   ```bash
   git -C <workspace>/repos/<category>/<repo> branch -D <branch>
   ```

7. **Report** what was cleaned up — the script's deleted/kept lists, any branches you deleted in step 6, and any kept because their PR is still open.
