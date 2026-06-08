#!/usr/bin/env bats
# Config validation for setup/litellm/config.yaml
# Covers: AC-7 (YAML parses, aliases unique, no hardcoded keys, walter-embed exists)
# Also validates AC-1 (>=20 entries) as a prerequisite for the expansion task.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CONFIG="$REPO_ROOT/setup/litellm/config.yaml"
}

# AC-7: YAML parses cleanly
@test "config.yaml parses as valid YAML [AC-7]" {
  python3 -c "import yaml, sys; yaml.safe_load(open('$CONFIG'))" 2>&1
  [ $? -eq 0 ]
}

# AC-7: all model_name aliases are unique
@test "all model_name aliases are unique [AC-7]" {
  total=$(python3 -c "
import yaml
data = yaml.safe_load(open('$CONFIG'))
names = [m['model_name'] for m in data.get('model_list', [])]
print(len(names))
")
  unique=$(python3 -c "
import yaml
data = yaml.safe_load(open('$CONFIG'))
names = [m['model_name'] for m in data.get('model_list', [])]
print(len(set(names)))
")
  [ "$total" -eq "$unique" ]
}

# AC-7: no hardcoded api_key literals (all must use os.environ/ or be absent)
@test "no hardcoded api_key values (all use os.environ/) [AC-7]" {
  # Uses python3 to parse YAML properly — avoids BSD grep's lack of PCRE lookahead.
  run python3 -c "
import yaml, sys
with open('$CONFIG') as f:
    data = yaml.safe_load(f)
bad = []
for entry in data.get('model_list', []):
    key = entry.get('litellm_params', {}).get('api_key', '')
    if key and not key.startswith('os.environ/'):
        bad.append(entry.get('model_name'))
if bad:
    print('hardcoded api_key in:', bad)
    sys.exit(1)
"
  [ "$status" -eq 0 ]
}

# AC-7: walter-embed entry exists
@test "walter-embed model entry exists [AC-7]" {
  result=$(python3 -c "
import yaml
data = yaml.safe_load(open('$CONFIG'))
names = [m['model_name'] for m in data.get('model_list', [])]
print('found' if 'walter-embed' in names else 'missing')
")
  [ "$result" = "found" ]
}

@test "claude shorthand model entry exists [AC-7]" {
  result=$(python3 -c "
import yaml
data = yaml.safe_load(open('$CONFIG'))
names = [m['model_name'] for m in data.get('model_list', [])]
print('found' if 'claude' in names else 'missing')
")
  [ "$result" = "found" ]
}

# AC-1: at least 20 model entries
@test "config has at least 20 model entries [AC-1]" {
  count=$(python3 -c "
import yaml
data = yaml.safe_load(open('$CONFIG'))
print(len(data.get('model_list', [])))
")
  [ "$count" -ge 20 ]
}
