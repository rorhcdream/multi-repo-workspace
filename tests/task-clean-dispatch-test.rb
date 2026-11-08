require "tmpdir"
require "fileutils"
require "open3"
require "json"

script = File.expand_path("../scripts/task-clean-dispatch.sh", __dir__)

Dir.mktmpdir("task-clean-dispatch-") do |root|
  workspace = File.join(root, "workspace with spaces")
  task = "task 'quoted'"
  bin = File.join(root, "bin")
  capture = File.join(root, "tmux-args")
  FileUtils.mkdir_p([File.join(workspace, "tasks", task), bin])
  workspace = File.realpath(workspace)
  File.write(File.join(workspace, ".workspace"), "")
  File.write(File.join(bin, "tmux"), <<~'RUBY')
    #!/usr/bin/env ruby
    require "json"
    File.open(ENV.fetch("DISPATCH_CAPTURE"), "a") { |file| file.puts(JSON.generate(ARGV)) }
    case ARGV.first
    when "list-panes"
      # tmux substitutes fields but does not expand a literal backslash-t.
      format = ARGV.fetch(ARGV.index("-F") + 1)
      puts format.gsub('#{pane_current_path}', ENV.fetch("ROOT_PANE_PATH")).gsub('#{pane_id}', "%9") unless ENV["NO_ROOT"] == "1"
    when "display-message"
      case ARGV.last
      when '#{pane_current_command}' then puts ENV.fetch("AGENT_CMD")
      when '#{pane_pid}' then puts "900"
      when '#{pane_in_mode}' then puts ENV.fetch("COPY_MODE", "0")
      else abort "Unexpected tmux query"
      end
    when "send-keys"
    else abort "Unexpected tmux mutation"
    end
  RUBY
  File.write(File.join(bin, "ps"), <<~'SH')
    #!/bin/bash
    printf '%s\n' "$PROCESS_TABLE"
  SH
  FileUtils.chmod(0755, Dir.glob(File.join(bin, "*")))
  env = {
    "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
    "TMUX" => "test-server",
    "TMUX_PANE" => "%1",
    "DISPATCH_CAPTURE" => capture,
    "ROOT_PANE_PATH" => workspace,
    "PROCESS_TABLE" => "900 1 zsh zsh\n901 900 node node /opt/codex/bin/codex\n902 1 claude claude"
  }

  [["codex", '$task-clean', "1"], ["claude", "/task-clean", "0"], ["node", '$task-clean', "1"],
   ["2.1.312", "/task-clean", "0"]].each do |command, prefix, copy_mode|
    FileUtils.rm_f(capture)
    selected_env = env.merge("AGENT_CMD" => command, "COPY_MODE" => copy_mode)
    if command == "2.1.312"
      selected_env["PROCESS_TABLE"] = "900 1 zsh zsh\n901 900 /opt/claude/versions/2.1.312 claude"
    end
    output, error, status = Open3.capture3(selected_env,
      "bash", script, workspace, task, chdir: File.join(workspace, "tasks", task))
    raise error unless status.success?
    raise "Missing root pane ID" unless output.include?("%9")
    calls = File.readlines(capture).map { |line| JSON.parse(line) }
    sends = calls.select { |args| args.first == "send-keys" }
    expected = [
      ["send-keys", "-t", "%9", "-l", "--", "#{prefix} #{task}"],
      ["send-keys", "-t", "%9", "Enter"]
    ]
    expected.unshift(["send-keys", "-t", "%9", "-X", "cancel"]) if copy_mode == "1"
    raise "Incorrect literal-text dispatch, copy-mode handling, or submit order" unless sends == expected
    raise "Must not create or select a window" if calls.any? { |args| %w[new-window select-window].include?(args.first) }
  end

  [{"TMUX" => ""}, {"NO_ROOT" => "1"}, {"ROOT_PANE_PATH" => File.join(workspace,"tasks",task)},
   {"AGENT_CMD" => "zsh", "PROCESS_TABLE" => "900 1 zsh zsh\n902 1 codex codex"},
   {"TMUX_PANE" => "%9"}].each do |override|
    FileUtils.rm_f(capture)
    _, _, status = Open3.capture3(env.merge("AGENT_CMD" => "codex").merge(override), "bash", script, workspace, task)
    raise "Unsafe dispatch should be blocked" if status.success?
    calls = File.exist?(capture) ? File.readlines(capture).map { |line| JSON.parse(line) } : []
    raise "Blocked dispatch must not send keys" if calls.any? { |args| args.first == "send-keys" }
  end
  ["..", "../other-task", "missing-task", "bad\nname"].each do |invalid_task|
    _, _, status = Open3.capture3(env, "bash", script, workspace, invalid_task)
    raise "Invalid task should block dispatch" if status.success?
  end
  raise "Dispatch must not remove the task" unless File.directory?(File.join(workspace, "tasks", task))
end

puts "task-clean dispatch tests passed"
