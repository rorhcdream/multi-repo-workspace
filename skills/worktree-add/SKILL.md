---
name: worktree-add
description: Manually add one or more source repositories as Git worktrees in the current multi-repo workspace task directory, primarily to make them available locally for convenient reading and optionally later editing. Use only when the user explicitly invokes `/worktree-add` and names repositories — never invoke this on your own initiative.
allowed-tools: Bash, Glob
---

Add one or more repository worktrees to the current task directory.

Arguments: $ARGUMENTS

> **Codex compatibility**: `${CLAUDE_PLUGIN_ROOT}` is Claude Code's plugin-root variable — under Codex, substitute this plugin's root directory (two levels above this SKILL.md). Steps that say to run with `dangerouslyDisableSandbox: true` mean, under Codex, running the command with escalated permissions (approve the sandbox escalation).

## Steps

1. **Find the workspace root** by locating the nearest `.workspace` marker in the current directory or an ancestor. If none exists, tell the user to run `/workspace-init` first.

2. **Identify the current task.** Resolve the current directory to an absolute path and verify that it is `<workspace>/tasks/<task-name>/` or a descendant of that directory. Derive `<task-name>` from the first path component below `tasks/`. If the command is not running inside a task, list the directories under `<workspace>/tasks/` and ask the user which task to use. Do not add a worktree at the workspace root.

3. **Resolve the repository arguments.** Accept one or more repositories, each in either form:
   - `<repo>`
   - `<category>/<repo>`

   For example, `/worktree-add api web tools/cli` selects three repositories. Deduplicate repeated selections.

   A custom branch description is supported only when adding one repository. Prefer `/worktree-add <repo> --branch-desc <branch-desc>`. For backward compatibility, if there are exactly two positional arguments, the first resolves to a repository, and the second does not resolve to any repository, treat the second as `<branch-desc>`. If every positional argument resolves, treat every one as a repository. By default, use each repository's `<repo>` basename as its branch description.

   For each bare `<repo>`, search exactly one directory level below every `<workspace>/repos/<category>/`. If there are no exact basename matches, report that the repository was not found. If there are multiple matches, list only their `category/repo` paths and ask the user to invoke the skill with one of those paths. For `<category>/<repo>`, verify that the exact source directory exists. Resolve every argument before creating anything; if any selection is missing or ambiguous, stop without adding a partial set.

4. **Check every destination before changing anything.** Each target is `<workspace>/tasks/<task-name>/<repo>`.
   - If it is already a Git worktree of the selected source repository, mark that repository as already available at `./<repo>` and continue checking the remaining selections. Compare the resolved common Git directory of the target with that of the source repository; do not rely only on the directory name.
   - If the path exists but is not a worktree of the selected source repository, stop and ask the user to choose how to resolve the collision. Never overwrite or delete it.
   - For repositories not already available, validate `<task-name>/<branch-desc>` with `git check-ref-format --branch`. If it is invalid or that local branch already exists in the source repository, report the problem and ask for a different branch description.

   Complete this preflight for the entire set before creating any worktree.

5. **Create each missing worktree** with the existing helper. Run it once per repository with `dangerouslyDisableSandbox: true` because it fetches from the remote and writes to the source repository's Git metadata:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-add.sh \
     "<workspace>" "<task-name>" "<category>" "<repo>" "<branch-desc>"
   ```
   The helper fetches the remote default branch and creates `<task-name>/<branch-desc>` from the latest `origin/<default>`. If a helper call fails, stop further additions and report both the failure and any repositories already added; do not roll back successful worktrees.

6. **Report the results** for every requested repository, distinguishing newly added and already-available worktrees. Include each task-relative path (`./<repo>`), branch name, and base branch. Mention that reading and editing must now use the task worktrees rather than the read-only source clones.

## Rules

- Add only the repositories explicitly named by the user.
- Treat adding a worktree solely for easier reading as intentional when the user invokes this skill.
- Never edit or create branches directly in `<workspace>/repos/`; use it only as the source repository for the worktree operation.
- Never add unrelated repositories or update every source repository.
