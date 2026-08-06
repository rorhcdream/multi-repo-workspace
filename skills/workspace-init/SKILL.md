---
name: workspace-init
description: This skill should be used when the user asks to "initialize workspace", "set up workspace", "create workspace", or wants to set up a new multi-repo workspace with copy-on-write semantics. Clones repos from source directories, creates the directory structure, and generates workspace configuration. Typically run once per workspace.
allowed-tools: Bash, Read, Write, Glob, Grep
---

Initialize a multi-repo workspace with copy-on-write semantics.

Arguments: $ARGUMENTS

## Steps

1. **Determine workspace root.** Use the current directory, or a path from the user's arguments.

2. **Ask the user for category names** if not provided in arguments. Categories are names for groups of repos (e.g., `org`, `public`, `personal`). The user can provide any names that make sense for their workflow. Also ask if they have source directories to clone from for each category.

3. **Create directory structure:**
   ```bash
   mkdir -p <workspace>/repos/<category>  # for each category
   mkdir -p <workspace>/tasks
   mkdir -p <workspace>/.claude
   ```

4. **Create `.claude/multi-repo-workspace.local.md`** with category configuration:
   ```markdown
   ---
   categories:
     - <category1>
     - <category2>
   ---
   ```

5. **Clone repos** from source directories (if the user provided any):
   ```bash
   for repo in <source-dir>/*/; do
     name=$(basename "$repo")
     if [ -d "$repo/.git" ] && [ ! -d "<workspace>/repos/<category>/$name" ]; then
       origin=$(git -C "$repo" remote get-url origin 2>/dev/null)
       if [ -n "$origin" ]; then
         git clone "$origin" "<workspace>/repos/<category>/$name"
       fi
     fi
   done
   ```
   Clone using each repo's origin remote URL so the workspace repos point to the correct upstream (e.g., GitHub), not the local source directory. Skip repos without an origin remote. Skip if already cloned. If no source directory was given for a category, leave `repos/<category>/` empty for the user to populate manually.

6. **Create `.workspace` marker:**
   ```bash
   touch <workspace>/.workspace
   ```

7. **Create `CLAUDE.md`** at the workspace root with the workspace rules:

   ```markdown
   # Multi-repo Workspace

   This workspace is managed by the multi-repo-workspace plugin.

   ## Layout
   - `repos/` — Read-only clones. Never edit directly.
   - `tasks/` — Active task worktrees. Edit here.
   - Use `/workspace` to see workspace status.
   - Use `/task-start <description>` to begin a new task.
   - Use `/task-clean` to clean up completed tasks.

   ## Usage
   `/task-start` launches the selected agent in a new tmux window (add `--nvim`
   to run it inside Neovim via sidecar.nvim). Outside tmux, run the command
   printed by the setup script:
   ```
   cd <workspace>/tasks/<task-name>
   claude "$(cat prompt.md)"
   ```
   Codex is launched with `--sandbox workspace-write`, keeping repos/ read-only.
   Claude uses its sandbox plus the PreToolUse hook that blocks Edit/Write to repos/.

   ## Rules
   - repos/ is read-only. To modify a repo, create a worktree under tasks/.
   - Reading repos/ is free and unrestricted.
   ```

8. **Report summary:** how many repos cloned per category, total workspace size.
