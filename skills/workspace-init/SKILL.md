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
       git clone "$repo" "<workspace>/repos/<category>/$name"
     fi
   done
   ```
   Only clone directories that are git repos. Skip if already cloned. If no source directory was given for a category, leave `repos/<category>/` empty for the user to populate manually.

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
   After `/task-start`, launch Claude Code from the task directory:
   ```
   cd <workspace>/tasks/<task-name>
   claude
   ```
   The sandbox automatically restricts Bash writes to the task directory.
   The PreToolUse hook blocks Edit/Write to repos/ as an additional safety net.

   ## Rules
   - repos/ is read-only. To modify a repo, create a worktree under tasks/.
   - Reading repos/ is free and unrestricted.
   ```

8. **Report summary:** how many repos cloned per category, total workspace size.
