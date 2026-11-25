require 'json'
require 'open3'

def session_directory(path)
  File.open(path) do |file|
    metadata = JSON.parse(file.readline)
    return unless metadata['type'] == 'session_meta'
    return unless metadata.dig('payload', 'source') == 'cli'

    cwd = metadata.dig('payload', 'cwd')
    file.each_line do |line|
      begin
        record = JSON.parse(line)
      rescue JSON::ParserError
        next
      end
      cwd = record.dig('payload', 'cwd') if record['type'] == 'turn_context'
    end
    cwd if cwd.is_a?(String) && !cwd.include?("\n") && File.directory?(cwd)
  end
rescue SystemCallError, EOFError, JSON::ParserError
  nil
end

pid = ARGV.fetch(0, '')
exit unless pid.match?(/\A[1-9][0-9]*\z/)

begin
  files, = Open3.capture2('/usr/sbin/lsof', '-nP', '-a', '-p', pid, '-Fn', err: File::NULL)
  rollouts = files.each_line.map do |line|
    next unless line.start_with?('n/')
    path = line[1..-1].chomp
    path if File.basename(path).match?(/\Arollout-.*\.jsonl\z/)
  end.compact.uniq
  directories = rollouts.map { |path| session_directory(path) }.compact.uniq
  puts directories.first if directories.length == 1
rescue SystemCallError
  # Keep the normal pane-directory fallback when process inspection is unavailable.
end
