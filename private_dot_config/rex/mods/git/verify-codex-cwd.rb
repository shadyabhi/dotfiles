require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'

# Exercise real open file descriptors, including delegated threads and damaged logs.
resolver = File.join(__dir__, 'codex-cwd.rb')
Dir.mktmpdir('rex-codex-cwd-') do |directory|
  checkout = File.join(directory, 'checkout')
  worktree = File.join(directory, "worktree with ' quotes")
  FileUtils.mkdir_p([checkout, worktree])
  root = File.join(directory, 'rollout-root.jsonl')
  child = File.join(directory, 'rollout-child.jsonl')
  meta = lambda { |cwd, source| {type: 'session_meta', payload: {cwd: cwd, source: source}}.to_json + "\n" }
  context = lambda { |cwd| {type: 'turn_context', payload: {cwd: cwd}}.to_json + "\n" }
  File.write(root, meta.call(checkout, 'cli') + context.call(worktree) + '{incomplete')
  File.write(child, meta.call(checkout, {'subagent' => {}}))

  File.open(root) do
    File.open(child) do
      check = lambda do |name, expected|
        output, status = Open3.capture2('/usr/bin/ruby', resolver, Process.pid.to_s)
        abort "FAIL: #{name}: #{output.inspect}" unless status.success? && output.chomp == expected
        puts "PASS: #{name}"
      end
      check.call('latest root context, spaces and quotes, incomplete trailing record, subagent ignored', worktree)
      File.write(root, meta.call(worktree, 'cli'))
      check.call('session metadata before first turn', worktree)
      File.write(root, meta.call(worktree, {'subagent' => {}}))
      check.call('subagent alone cannot select a directory', '')
      File.write(root, meta.call(File.join(directory, 'deleted'), 'cli'))
      check.call('missing directory falls back', '')
      File.write(root, meta.call(worktree, 'cli'))
      File.write(child, meta.call(checkout, 'cli'))
      check.call('ambiguous root sessions fall back', '')
    end
  end
end
