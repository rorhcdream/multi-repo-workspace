require "tmpdir"
require "fileutils"
require "open3"

script = File.expand_path("../scripts/task-clean.sh", __dir__)

[
  ["tmp/finish-pr-notified-90802.txt", true],
  ["tmp/nested/arbitrary.txt", true],
  ["nested/tmp/arbitrary.txt", true],
  ["atmp/keep.txt", false],
  ["tmp.txt", false],
  ["src/keep.txt", false],
  ["nohup.out", true],
  ["nested/run.log", true],
  ["work.txt", true, "tmp/repo"],
  ["work.txt", true, "nested/tmp/repo"],
  ["work.txt", false, "nested/atmp/repo"]
].each do |path, disposable, repo_path|
  Dir.mktmpdir("task-clean-") do |workspace|
    task_dir = File.join(workspace, "tasks", "example")
    repo = File.join(task_dir, repo_path || "repo")
    FileUtils.mkdir_p(repo)
    _, error, status = Open3.capture3("git", "init", "--quiet", repo)
    raise error unless status.success?
    file = File.join(repo, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "fixture")
    output, error, status = Open3.capture3(
      {"TMUX" => "", "TASK_CLEAN_IGNORE" => nil}, "bash", script, workspace, "example")
    if disposable
      raise "Disposable #{path} blocked cleanup: #{output}#{error}" unless status.success?
      raise "Task was not removed" if File.exist?(task_dir)
    else
      raise "Real work #{path} did not block cleanup: #{output}#{error}" unless status.exitstatus == 2
      raise "Real work was removed" unless File.read(file) == "fixture"
    end
  end
end

puts "task-clean tests passed"
