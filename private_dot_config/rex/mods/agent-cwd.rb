require 'json'
require 'open3'

def codex_directory(path)
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

def claude_directory(path)
  session_id = File.basename(path, '.jsonl')
  return unless session_id.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)
  cwd = nil
  File.foreach(path) do |line|
    begin
      record = JSON.parse(line)
    rescue JSON::ParserError
      next
    end
    next unless record['sessionId'] == session_id && record['isSidechain'] == false
    cwd = record['cwd'] if record['cwd'].is_a?(String)
  end
  cwd if cwd.is_a?(String) && !cwd.include?("\n") && File.directory?(cwd)
rescue SystemCallError
  nil
end

pid = ARGV.fetch(0, '')
exit unless pid.match?(/\A[1-9][0-9]*\z/)
agent = ARGV.fetch(1, 'codex')
read_directory = { 'codex' => method(:codex_directory), 'claude' => method(:claude_directory) }[agent]
exit unless read_directory

begin
  files, = Open3.capture2('/usr/sbin/lsof', '-nP', '-a', '-p', pid, '-Fn', err: File::NULL)
  transcripts = files.each_line.map do |line|
    next unless line.start_with?('n/')
    path = line[1..-1].chomp
    next unless path.end_with?('.jsonl')
    next if agent == 'codex' && !File.basename(path).match?(/\Arollout-.*\.jsonl\z/)
    path
  end.compact.uniq
  directories = transcripts.map { |path| read_directory.call(path) }.compact.uniq
  puts directories.first if directories.length == 1
rescue SystemCallError
  # Keep the normal pane-directory fallback when process inspection is unavailable.
end
