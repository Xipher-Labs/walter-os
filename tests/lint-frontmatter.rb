#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

REPO_ROOT = File.expand_path("..", __dir__)
Dir.chdir(REPO_ROOT)

GREEN = "\e[32m"
RED = "\e[31m"
RESET = "\e[0m"

CODEX_SKILL_NAME_MAX = Integer(ENV.fetch("CODEX_SKILL_NAME_MAX", "64"))
CODEX_SKILL_DESCRIPTION_MAX = Integer(ENV.fetch("CODEX_SKILL_DESCRIPTION_MAX", "1024"))

REQUIRED_FIELDS = {
  "skill" => %w[name description],
  "agent" => %w[name description tools model],
  "command" => %w[description]
}.freeze

def frontmatter_from(path)
  text = File.read(path)
  return [nil, "missing frontmatter"] unless text.match?(/\A---\r?\n/)

  parts = text.split(/^---\s*$/m, 3)
  return [nil, "missing frontmatter"] if parts.length < 3 || parts[1].strip.empty?

  [parts[1], nil]
end

def parse_yaml(frontmatter)
  data = YAML.safe_load(
    frontmatter,
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false
  )
  return [nil, "frontmatter must parse to a YAML mapping"] unless data.is_a?(Hash)

  [data, nil]
rescue Psych::Exception => e
  [nil, "invalid YAML frontmatter: #{e.message.gsub(/[[:space:]]+/, " ")}"]
end

def validate_required_fields(data, kind)
  REQUIRED_FIELDS.fetch(kind).each do |field|
    next if data.key?(field) && !data[field].nil? && data[field] != ""

    return "missing '#{field}' in frontmatter"
  end

  nil
end

def validate_skill_metadata(data)
  name = data["name"]
  description = data["description"]

  return "'name' must be a string" unless name.is_a?(String)
  return "'description' must be a string" unless description.is_a?(String)
  if name.length > CODEX_SKILL_NAME_MAX
    return "'name' exceeds Codex loader limit (#{name.length} > #{CODEX_SKILL_NAME_MAX})"
  end
  if description.length > CODEX_SKILL_DESCRIPTION_MAX
    return "'description' exceeds Codex loader limit (#{description.length} > #{CODEX_SKILL_DESCRIPTION_MAX})"
  end
  return "description suspiciously short (#{description.length} chars)" if description.length < 50

  nil
end

def validate(path, kind)
  frontmatter, error = frontmatter_from(path)
  return error if error

  data, error = parse_yaml(frontmatter)
  return error if error

  error = validate_required_fields(data, kind)
  return error if error

  validate_skill_metadata(data) if kind == "skill"
end

def check_group(kind, heading, pattern)
  puts heading

  failures = 0
  Dir[pattern].sort.each do |path|
    error = validate(path, kind)
    if error
      puts "#{RED}✗#{RESET} #{path} — #{error}"
      failures += 1
    else
      puts "#{GREEN}✓#{RESET} #{path}"
    end
  end

  failures
end

failures = 0
failures += check_group("skill", "Linting skills/*/SKILL.md...", "skills/*/SKILL.md")
puts
failures += check_group("agent", "Linting agents/*.md...", "agents/*.md")
puts
failures += check_group("command", "Linting commands/*.md...", "commands/*.md")
puts

if failures.positive?
  puts "#{RED}#{failures} frontmatter failure(s).#{RESET}"
  exit 1
end

puts "#{GREEN}All frontmatter clean.#{RESET}"
