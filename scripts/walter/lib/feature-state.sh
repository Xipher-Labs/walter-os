#!/usr/bin/env bash
# scripts/walter/lib/feature-state.sh
#
# Persistent feature-state ledger helpers for AD-2. This library manages
# repository-local runtime state only; policy remains in walter-repo-config.yaml.

walter_feature_state_require_ruby() {
  if ! command -v ruby >/dev/null 2>&1; then
    printf 'feature-state: ruby is required for YAML state operations\n' >&2
    return 4
  fi
}

walter_feature_state_validate_id() {
  local id="${1:-}"
  if [[ -z "$id" ]] || [[ "$id" == *".."* ]] || [[ "$id" == *"/"* ]] \
      || ! [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$ ]]; then
    printf 'feature-state: invalid feature id: %s\n' "$id" >&2
    return 64
  fi
}

walter_feature_state_repo_root() {
  local repo="${1:-}"
  local git_root
  if [[ -n "$repo" ]]; then
    printf '%s\n' "${repo%/}"
    return 0
  fi

  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$git_root"
  else
    pwd -P
  fi
}

walter_feature_state_path() {
  local repo="$1" id="$2"
  printf '%s/.walter/features/%s/state.yaml\n' "${repo%/}" "$id"
}

_walter_feature_state_init_unlocked() {
  ruby <<'RUBY'
require "fileutils"
require "time"
require "yaml"

path = ENV.fetch("FEATURE_STATE_PATH")
lock_path = ENV.fetch("FEATURE_LOCK_PATH")
force = ENV.fetch("FEATURE_FORCE", "0") == "1"

FileUtils.mkdir_p(File.dirname(path))
File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
  lock.flock(File::LOCK_EX)

  if File.exist?(path) && !force
    warn "feature-state: already exists: #{path}"
    exit 1
  end

  now = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  state = {
    "schema_version" => 1,
    "id" => ENV.fetch("FEATURE_ID"),
    "title" => ENV.fetch("FEATURE_TITLE", ""),
    "issue" => ENV.fetch("FEATURE_ISSUE", ""),
    "stage" => "idea",
    "created_at" => now,
    "updated_at" => now,
    "idea" => ENV.fetch("FEATURE_IDEA", ""),
    "brief" => {
      "summary" => "",
      "links" => []
    },
    "spec" => {
      "path" => ENV.fetch("FEATURE_SPEC_PATH", ""),
      "status" => "not-started"
    },
    "acceptance_criteria" => [],
    "tasks" => [],
    "decisions" => [],
    "risks" => [],
    "prs" => [],
    "post_merge" => []
  }

  tmp = "#{path}.tmp.#{$$}"
  File.write(tmp, state.to_yaml)
  File.rename(tmp, path)
  puts "feature-state: initialized #{path}"
end
RUBY
}

walter_feature_state_init() {
  local repo="$1" id="$2" title="$3" issue="$4" idea="$5" spec_path="$6" force="$7"
  walter_feature_state_require_ruby || return $?
  walter_feature_state_validate_id "$id" || return $?

  local path dir lock_file
  path="$(walter_feature_state_path "$repo" "$id")"
  dir="$(dirname "$path")"
  mkdir -p "$dir"
  lock_file="${path}.lock"

  FEATURE_STATE_PATH="$path" \
  FEATURE_ID="$id" \
  FEATURE_TITLE="$title" \
  FEATURE_ISSUE="$issue" \
  FEATURE_IDEA="$idea" \
  FEATURE_SPEC_PATH="$spec_path" \
  FEATURE_FORCE="$force" \
  FEATURE_LOCK_PATH="$lock_file" \
    _walter_feature_state_init_unlocked
}

_walter_feature_state_validate_file() {
  FEATURE_STATE_PATH="$1" ruby <<'RUBY'
require "yaml"

path = ENV.fetch("FEATURE_STATE_PATH")

begin
  raw = File.read(path)
  begin
    state = YAML.safe_load(raw, aliases: false)
  rescue ArgumentError
    state = YAML.safe_load(raw)
  end
rescue StandardError => e
  warn "feature-state: invalid: #{path}: #{e.message}"
  exit 1
end

unless state.is_a?(Hash)
  warn "feature-state: invalid: #{path}: expected YAML mapping"
  exit 1
end

POLICY_KEYS = %w[
  approval_gate
  approval_overrides
  approval_policy
  autonomy_mode
  auto_merge
  capability_tier_ceiling
  hard_limit_overrides
  human_approval_required_for
  permissions
  preview_deploy
  profile
  verification
].freeze

def reject_policy_keys!(value, trail = [])
  case value
  when Hash
    value.each do |key, child|
      key_name = key.to_s
      path = trail + [key_name]
      if POLICY_KEYS.include?(key_name)
        warn "feature-state: invalid: state file cannot declare policy key: #{path.join(".")}"
        exit 1
      end
      reject_policy_keys!(child, path)
    end
  when Array
    value.each_with_index do |child, index|
      reject_policy_keys!(child, trail + [index.to_s])
    end
  end
end

reject_policy_keys!(state)

required = %w[
  schema_version
  id
  title
  issue
  stage
  created_at
  updated_at
  idea
  brief
  spec
  acceptance_criteria
  tasks
  decisions
  risks
  prs
  post_merge
]

missing = required.reject { |key| state.key?(key) }
unless missing.empty?
  warn "feature-state: invalid: #{path}: missing required field(s): #{missing.join(", ")}"
  exit 1
end

unless state["schema_version"] == 1
  warn "feature-state: invalid: #{path}: schema_version must be 1"
  exit 1
end

unless state["id"].is_a?(String) && state["id"].match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,79}\z/) && !state["id"].include?("..")
  warn "feature-state: invalid: #{path}: invalid id"
  exit 1
end

path_id = File.basename(File.dirname(path))
if path_id != state["id"]
  warn "feature-state: invalid: #{path}: id does not match directory name"
  exit 1
end

unless state["title"].is_a?(String) && state["issue"].is_a?(String) && state["idea"].is_a?(String)
  warn "feature-state: invalid: #{path}: title, issue, and idea must be strings"
  exit 1
end

unless state["brief"].is_a?(Hash) && state["spec"].is_a?(Hash)
  warn "feature-state: invalid: #{path}: brief and spec must be mappings"
  exit 1
end

%w[acceptance_criteria tasks decisions risks prs post_merge].each do |key|
  unless state[key].is_a?(Array)
    warn "feature-state: invalid: #{path}: #{key} must be an array"
    exit 1
  end
end

valid_stages = %w[
  idea
  brief
  spec
  tasks
  implementation
  review
  merged
  post-merge-healthy
  post-merge-investigate
  rollback-recommended
  human-escalation
]

unless valid_stages.include?(state["stage"])
  warn "feature-state: invalid: #{path}: invalid stage: #{state["stage"]}"
  exit 1
end
RUBY
}

walter_feature_state_validate_target() {
  local target="${1:-$(pwd)}"
  local -a files

  walter_feature_state_require_ruby || return $?

  if [[ -f "$target" ]]; then
    files=("$target")
  elif [[ -d "$target" ]]; then
    shopt -s nullglob
    files=("${target%/}"/.walter/features/*/state.yaml)
    shopt -u nullglob
  else
    printf 'feature-state: target not found: %s\n' "$target" >&2
    return 1
  fi

  if [[ "${#files[@]}" -eq 0 ]]; then
    printf 'feature-state: no feature state ledgers found under %s\n' "$target" >&2
    return 1
  fi

  local file display
  for file in "${files[@]}"; do
    _walter_feature_state_validate_file "$file" || return $?
    display="$file"
    if [[ -d "$target" && "$file" == "${target%/}/"* ]]; then
      display="${file#"${target%/}/"}"
    fi
    printf 'feature-state: valid %s\n' "$display"
  done
}

_walter_feature_state_record_post_merge_unlocked() {
  ruby <<'RUBY'
require "time"
require "yaml"

path = ENV.fetch("FEATURE_STATE_PATH")
lock_path = ENV.fetch("FEATURE_LOCK_PATH")
decision = ENV.fetch("FEATURE_DECISION")
next_action = ENV.fetch("FEATURE_NEXT_ACTION")
merge_sha = ENV.fetch("FEATURE_MERGE_SHA")
source = ENV.fetch("FEATURE_SOURCE")

POLICY_KEYS = %w[
  approval_gate
  approval_overrides
  approval_policy
  autonomy_mode
  auto_merge
  capability_tier_ceiling
  hard_limit_overrides
  human_approval_required_for
  permissions
  preview_deploy
  profile
  verification
].freeze

def reject_policy_keys!(value, trail = [])
  case value
  when Hash
    value.each do |key, child|
      key_name = key.to_s
      state_path = trail + [key_name]
      if POLICY_KEYS.include?(key_name)
        warn "feature-state: invalid: state file cannot declare policy key: #{state_path.join(".")}"
        exit 1
      end
      reject_policy_keys!(child, state_path)
    end
  when Array
    value.each_with_index do |child, index|
      reject_policy_keys!(child, trail + [index.to_s])
    end
  end
end

def load_state!(path)
  raw = File.read(path)
  begin
    YAML.safe_load(raw, aliases: false)
  rescue ArgumentError
    YAML.safe_load(raw)
  end
rescue StandardError => e
  warn "feature-state: invalid: #{path}: #{e.message}"
  exit 1
end

def validate_state!(path, state)
  unless state.is_a?(Hash)
    warn "feature-state: invalid: #{path}: expected YAML mapping"
    exit 1
  end

  reject_policy_keys!(state)

  required = %w[
    schema_version
    id
    title
    issue
    stage
    created_at
    updated_at
    idea
    brief
    spec
    acceptance_criteria
    tasks
    decisions
    risks
    prs
    post_merge
  ]

  missing = required.reject { |key| state.key?(key) }
  unless missing.empty?
    warn "feature-state: invalid: #{path}: missing required field(s): #{missing.join(", ")}"
    exit 1
  end

  unless state["schema_version"] == 1
    warn "feature-state: invalid: #{path}: schema_version must be 1"
    exit 1
  end

  unless state["id"].is_a?(String) && state["id"].match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,79}\z/) && !state["id"].include?("..")
    warn "feature-state: invalid: #{path}: invalid id"
    exit 1
  end

  path_id = File.basename(File.dirname(path))
  if path_id != state["id"]
    warn "feature-state: invalid: #{path}: id does not match directory name"
    exit 1
  end

  unless state["title"].is_a?(String) && state["issue"].is_a?(String) && state["idea"].is_a?(String)
    warn "feature-state: invalid: #{path}: title, issue, and idea must be strings"
    exit 1
  end

  unless state["brief"].is_a?(Hash) && state["spec"].is_a?(Hash)
    warn "feature-state: invalid: #{path}: brief and spec must be mappings"
    exit 1
  end

  %w[acceptance_criteria tasks decisions risks prs post_merge].each do |key|
    unless state[key].is_a?(Array)
      warn "feature-state: invalid: #{path}: #{key} must be an array"
      exit 1
    end
  end

  valid_stages = %w[
    idea
    brief
    spec
    tasks
    implementation
    review
    merged
    post-merge-healthy
    post-merge-investigate
    rollback-recommended
    human-escalation
  ]

  unless valid_stages.include?(state["stage"])
    warn "feature-state: invalid: #{path}: invalid stage: #{state["stage"]}"
    exit 1
  end
end

stage = case decision
        when "healthy"
          "post-merge-healthy"
        when "investigate"
          "post-merge-investigate"
        when "rollback-recommended"
          "rollback-recommended"
        when "human-escalation"
          "human-escalation"
        else
          warn "feature-state: invalid decision: #{decision}"
          exit 64
        end

File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
  lock.flock(File::LOCK_EX)

  state = load_state!(path)
  validate_state!(path, state)

  now = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  state["post_merge"] << {
    "recorded_at" => now,
    "decision" => decision,
    "next_action" => next_action,
    "merge_sha" => merge_sha,
    "source" => source
  }
  state["stage"] = stage
  state["updated_at"] = now

  tmp = "#{path}.tmp.#{$$}"
  File.write(tmp, state.to_yaml)
  File.rename(tmp, path)
  puts "feature-state: recorded post-merge event #{path}"
end
RUBY
}

walter_feature_state_record_post_merge() {
  local repo="$1" id="$2" decision="$3" next_action="$4" merge_sha="$5" source="$6"
  walter_feature_state_require_ruby || return $?
  walter_feature_state_validate_id "$id" || return $?

  case "$decision" in
    healthy|investigate|rollback-recommended|human-escalation) ;;
    *)
      printf 'feature-state: invalid decision: %s\n' "$decision" >&2
      return 64
      ;;
  esac

  local path lock_file
  path="$(walter_feature_state_path "$repo" "$id")"
  if [[ ! -f "$path" ]]; then
    printf 'feature-state: ledger not found: %s\n' "$path" >&2
    return 1
  fi

  lock_file="${path}.lock"
  FEATURE_STATE_PATH="$path" \
  FEATURE_DECISION="$decision" \
  FEATURE_NEXT_ACTION="$next_action" \
  FEATURE_MERGE_SHA="$merge_sha" \
  FEATURE_SOURCE="$source" \
  FEATURE_LOCK_PATH="$lock_file" \
    _walter_feature_state_record_post_merge_unlocked
}
