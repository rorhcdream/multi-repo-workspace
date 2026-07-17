---
name: worktree-add
description: Manually add one source repository as a Git worktree in the current multi-repo workspace task directory, primarily to make the repository available locally for convenient reading and optionally later editing. Use only when the user explicitly invokes `/worktree-add` and names a repository.
disable-model-invocation: true
allowed-tools: Bash, Glob
---

Add one repository worktree to the current task directory.

Arguments: $ARGUMENTS

## Steps

1. **Find the workspace root** by locating the nearest `.workspace` marker in the current directory or an ancestor. If none exists, tell the user to run `/workspace-init` first.

2. **Identify the current task.** Resolve the current directory to an absolute path and verify that it is `<workspace>/tasks/<task-name>/` or a descendant of that directory. Derive `<task-name>` from the first path component below `tasks/`. If the command is not running inside a task, list the directories under `<workspace>/tasks/` and ask the user which task to use. Do not add a worktree at the workspace root.

3. **Resolve the repository argument.** Accept either form:
   - `<repo>`
   - `<category>/<repo>`

   Treat the optional second argument as `<branch-desc>`. If it is omitted, use `<repo>` as the branch description.

   For a bare `<repo>`, search exactly one directory level below every `<workspace>/repos/<category>/`. If there are no exact basename matches, report that the repository was not found. If there are multiple matches, list only their `category/repo` paths and ask the user to invoke the skill with one of those paths. For `<category>/<repo>`, verify that the exact source directory exists.

4. **Check the destination before changing anything.** The target is `<workspace>/tasks/<task-name>/<repo>`.
   - If it is already a Git worktree of the selected source repository, report that the repository is already available at `./<repo>` and stop successfully. Compare the resolved common Git directory of the target with that of the source repository; do not rely only on the directory name.
   - If the path exists but is not a worktree of the selected source repository, stop and ask the user to choose how to resolve the collision. Never overwrite or delete it.
   - Validate `<task-name>/<branch-desc>` with `git check-ref-format --branch`. If it is invalid or that local branch already exists in the source repository, report the problem and ask for a different branch description.

5. **Create the worktree** with the existing helper. Run it with `dangerouslyDisableSandbox: true` because it fetches from the remote and writes to the source repository's Git metadata:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-add.sh \
     "<workspace>" "<task-name>" "<category>" "<repo>" "<branch-desc>"
   ```
   The helper fetches the remote default branch and creates `<task-name>/<branch-desc>` from the latest `origin/<default>`.

6. **Report the result** with the task-relative path (`./<repo>`), branch name, and base branch. Mention that reading and editing must now use the task worktree rather than the read-only source clone.

## Rules

- Add exactly one repository per invocation.
- Treat adding a worktree solely for easier reading as intentional when the user invokes this skill.
- Never edit or create branches directly in `<workspace>/repos/`; use it only as the source repository for the worktree operation.
- Never add unrelated repositories or update every source repository.
