require "json"
require "open3"
require "tmpdir"
require "fileutils"

def rex(*args)
  stdout, stderr, status = Open3.capture3("rex", *args)
  raise "rex #{args.first}: #{stderr}" unless status.success?
  stdout.empty? ? nil : JSON.parse(stdout)
end

def await_cwd(session, block, expected)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
  loop do
    current = rex("block", "call", "-s", session, "-b", block, "process").dig("foreground", "cwd")
    return if current == expected
    raise "Expected #{expected.inspect}, got #{current.inspect}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.05
  end
end

def verify_shortcuts(session, source, expected, kind, rows)
  %w[s v].each do |key|
    before = rex("block", "ls", "-s", session, "--json").fetch("blocks").map { |b| b.fetch("block_id") }
    event = { session_id: session, block_id: source, prefix: ["ctrl+a"], key: {
      key: "key_#{key}", mods: "", consumed_mods: "", text: key,
      unshifted_codepoint: key.ord, composing: false, action: "press"
    } }
    result = rex("api", "call", "-s", session, "client.key", JSON.generate(event))
    raise "Ctrl+A #{key} did not handle the key" unless result.fetch("handled")
    blocks = rex("block", "ls", "-s", session, "--json").fetch("blocks").map { |b| b.fetch("block_id") }
    added = blocks - before
    raise "Expected one new pane, got #{added.length}" unless added.length == 1
    begin
      await_cwd(session, added.first, expected)
      view = rex("session", "inspect", session, "--json")
      window = view.fetch("windows").find { |w| w.fetch("focused_block_id") == added.first }
      raise "New pane was not focused" unless window
      direction = key == "s" ? "vertical" : "horizontal"
      layouts = window.fetch("layers").map { |l| l.fetch("layout") }
      splits = lambda do |node|
        split = node["split"]
        next [] unless split
        [split] + splits.call(split.fetch("before")) + splits.call(split.fetch("after"))
      end
      parent = layouts.flat_map { |node| splits.call(node) }.find { |s| s.dig("after", "block_id") == added.first }
      raise "Wrong split orientation or anchor" unless parent && parent.fetch("direction") == direction && parent.dig("before", "block_id") == source
      rows << "| #{kind} | Ctrl+A, #{key} | #{direction} | `#{expected}` | PASS |"
    ensure
      remaining = rex("block", "ls", "-s", session, "--json").fetch("blocks")
      rex("block", "close", "-s", session, added.first) if remaining.any? { |b| b.fetch("block_id") == added.first }
    end
  end
end

abort "Usage: ruby #{$PROGRAM_NAME} [SESSION SOURCE_BLOCK EXPECTED_DIRECTORY]" unless [0, 3].include?(ARGV.length)
rows = []
Dir.mktmpdir("rex split cwd ") do |directory|
  directory = File.realpath(directory)
  checkout = File.join(directory, "checkout")
  worktree = File.join(directory, "worktree with ' quotes")
  FileUtils.mkdir_p([checkout, worktree])
  %w[shell foreground codex claude].each do |kind|
    log = File.join(directory, "rollout-root.jsonl")
    child = File.join(directory, "rollout-child.jsonl")
    command = ["/bin/sleep", "120"]
    expected = checkout
    case kind
    when "shell"
      command = ["/bin/sh"]
    when "codex"
      expected = worktree
      File.write(log, {type: "session_meta", payload: {source: "cli", cwd: checkout}}.to_json + "\n" +
        {type: "turn_context", payload: {cwd: worktree}}.to_json + "\n{incomplete")
      File.write(child, {type: "session_meta", payload: {source: {subagent: {}}, cwd: checkout}}.to_json + "\n")
    when "claude"
      expected = worktree
      id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      log = File.join(directory, "#{id}.jsonl")
      child = File.join(directory, "agent-child.jsonl")
      records = [
        {type: "user", sessionId: id, isSidechain: false, cwd: checkout},
        {type: "assistant", sessionId: id, isSidechain: false, cwd: worktree},
        {type: "assistant", sessionId: id, isSidechain: true, cwd: checkout},
        {type: "assistant", sessionId: "another-session", isSidechain: false, cwd: checkout}
      ]
      File.write(log, records.map(&:to_json).join("\n") + "\n{incomplete")
      File.write(child, {type: "assistant", sessionId: id, isSidechain: true, cwd: checkout}.to_json + "\n")
    end
    if %w[codex claude].include?(kind)
      executable = File.join(directory, kind)
      FileUtils.cp("/opt/homebrew/bin/gsleep", executable)
      command = [executable, "120"]
    else
      File.write(log, "")
      File.write(child, "")
    end
    script = 'printf "\033]7;file://localhost/private/tmp\007"; cd "$1" || exit; exec 3< "$2"; exec 4< "$3"; shift 3; exec "$@"'
    created = rex("new", "split-cwd-verification", "-c", "/private/tmp", "--shell", "none", "--json", "--",
                  "/bin/sh", "-c", script, "split-cwd-check", checkout, log, child, *command)
    session = created.fetch("session_id")
    source = created.fetch("initial_windows").first.fetch("block_ids").first
    begin
      await_cwd(session, source, checkout)
      verify_shortcuts(session, source, expected, kind, rows)
    rescue StandardError
      warn "Failed case: #{kind}"
      warn Open3.capture2("rex", "capture", "-s", session, "-b", source, "--trim").first
      raise
    ensure
      rex("kill", session)
    end
  end
end

unless ARGV.empty?
  session, source, expected = ARGV
  view = rex("session", "inspect", session, "--json")
  focused = view.fetch("windows").find { |w| w.fetch("window_id") == view.fetch("active_window_id") }.fetch("focused_block_id")
  begin
    verify_shortcuts(session, source, File.realpath(expected), "existing agent pane", rows)
  ensure
    rex("focus", "-s", session, focused)
  end
end
report = "# Pane directory verification\n\nReal Rex key events verify directory, split direction, anchor, and focus. Shells and ordinary commands use process cwd despite stale OSC 7. Agent fixtures use real processes holding root and delegated session logs open, with a worktree different from process cwd, spaces and quotes, and an incomplete trailing log record. Claude fixtures also include records from unrelated sessions.\n\n| Process | Shortcut | Split | New pane directory | Result |\n| --- | --- | --- | --- | --- |\n#{rows.join("\n")}\n"
File.write("/tmp/rex-split-cwd-verification.md", report)
puts report
