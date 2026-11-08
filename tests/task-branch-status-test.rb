require "tmpdir"
require "fileutils"
require "open3"

script = File.expand_path("../scripts/task-branch-status.sh", __dir__)
cleanup = File.expand_path("../scripts/task-clean.sh", __dir__)

def run(*command)
  output, error, status = Open3.capture3(*command)
  raise error unless status.success?
  output.strip
end

Dir.mktmpdir("task-branch-status-") do |root|
  remote = File.join(root, "remote.git")
  repo = File.join(root, "repo with spaces")
  other = File.join(root, "other")
  run("git", "init", "--bare", "--initial-branch=main", remote)
  run("git", "clone", remote, repo)
  run("git", "-C", repo, "config", "user.name", "Test User")
  run("git", "-C", repo, "config", "user.email", "test@example.com")
  run("git", "-C", repo, "commit", "--allow-empty", "-m", "Initial")
  run("git", "-C", repo, "push", "origin", "main")
  run("git", "-C", repo, "switch", "-c", "task/change")
  File.write(File.join(repo, "change.txt"), "change")
  run("git", "-C", repo, "add", "change.txt")
  run("git", "-C", repo, "commit", "-m", "Task change")
  run("git", "-C", repo, "push", "-u", "origin", "task/change")
  state = run("bash", script, repo, "task/change")
  raise "Pushed feature branch is not landed" unless state.start_with?("UNCONFIRMED:")
  run("git", "clone", remote, other)
  run("git", "-C", other, "merge", "--ff-only", "origin/task/change")
  run("git", "-C", other, "push", "origin", "main")
  state = run("bash", script, repo, "task/change")
  raise "Direct landing must be recognized without a PR" unless state == "LANDED: origin/main"
  raise "Local default should remain behind (and untouched)" unless run("git", "-C", repo, "rev-parse", "main") != run("git", "-C", repo, "rev-parse", "origin/main")
  raise "Default branch must be protected" unless run("bash", script, repo, "main").start_with?("DEFAULT:")

  workspace = File.join(root, "workspace")
  FileUtils.mkdir_p(File.join(workspace, "tasks"))
  run("git", "-C", repo, "branch", "landed-task/change", "task/change")
  run("git", "-C", repo, "switch", "main")
  task_dir = File.join(workspace, "tasks", "landed-task")
  FileUtils.mkdir_p(task_dir)
  run("git", "-C", repo, "worktree", "add", File.join(task_dir,"repo"), "landed-task/change")
  run({"TMUX" => ""}, "bash", cleanup, workspace, "landed-task")
  raise "Landed task directory should be removed" if File.exist?(task_dir)
  _, _, status = Open3.capture3("git", "-C", repo, "show-ref", "--verify", "--quiet", "refs/heads/landed-task/change")
  raise "Landed branch should be deleted even with a stale local default" if status.success?

  task_dir = File.join(workspace, "tasks", "unlanded-task")
  FileUtils.mkdir_p(task_dir)
  worktree = File.join(task_dir, "repo")
  run("git", "-C", repo, "worktree", "add", "-b", "unlanded-task/change", worktree, "main")
  run("git", "-C", worktree, "commit", "--allow-empty", "-m", "Unlanded task")
  run("git", "-C", worktree, "push", "-u", "origin", "unlanded-task/change")
  output = run({"TMUX" => ""}, "bash", cleanup, workspace, "unlanded-task")
  raise "Clean unlanded task directory should still be removable" if File.exist?(task_dir)
  raise "Unlanded branch should be reported as retained" unless output.include?("Kept branches (check integration status before deleting): unlanded-task/change")
  run("git", "-C", repo, "show-ref", "--verify", "--quiet", "refs/heads/unlanded-task/change")

  run("git", "-C", repo, "remote", "set-url", "origin", File.join(root, "missing.git"))
  raise "Unavailable remote must not imply landed" unless run("bash", script, repo, "task/change").start_with?("UNKNOWN:")
  raise "Missing branch must not imply landed" unless run("bash", script, repo, "missing").start_with?("UNKNOWN:")
end

puts "task branch status tests passed"
