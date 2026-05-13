#!/usr/bin/env bats
# Tests for P0-06: load-lessons.sh must use proper JSON encoding for systemMessage.
# sed 's/"/\\"/g' is insufficient — it misses backslashes, newlines, control chars.
# See: docs/operational/security-audit-2026-05-11.md P0-06

LOAD_LESSONS="$BATS_TEST_DIRNAME/../../external/marchetto-agent-skills/skills/learn-by-mistake/hooks/scripts/load-lessons.sh"

setup() {
  TMPDIR_TEST=$(mktemp -d)
  LESSONS_FILE="$TMPDIR_TEST/.claude/lessons.md"
  mkdir -p "$TMPDIR_TEST/.claude"

  # Point hook at our temp dir by running from it
  cd "$TMPDIR_TEST"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "P0-06: load-lessons.sh exists" {
  [[ -f "$LOAD_LESSONS" ]]
}

@test "P0-06: output when no lessons file is valid JSON" {
  # No lessons file — should output the default message
  run bash "$LOAD_LESSONS"
  [[ "$status" -eq 0 ]]
  # Output must be valid JSON
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null
}

@test "P0-06: lessons with double-quotes produce valid JSON systemMessage" {
  # Lessons content with double quotes (the classic injection vector)
  cat > "$LESSONS_FILE" <<'EOF'
## Active Lessons

### [2026-05-01] shell: use "double quotes" around variables
Always use "double quotes" for variables in bash.

### [2026-05-02] python: prefer f-strings over "format()" calls
Use f-strings instead of "str.format()" for readability.
EOF

  run bash "$LOAD_LESSONS"
  [[ "$status" -eq 0 ]]
  # Output must be parseable JSON
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null
}

@test "P0-06: lessons with JSON-breaking sequences produce valid JSON" {
  # The real attack: content that breaks out of the JSON string
  cat > "$LESSONS_FILE" <<'MALESEOF'
## Active Lessons

### [2026-05-01] injection: test
This lesson contains: "}, "malicious": "inject"
and also backslash: \n \t \\
and control chars too.
MALESEOF

  run bash "$LOAD_LESSONS"
  [[ "$status" -eq 0 ]]
  # Output must be parseable JSON — this is the key test
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null
}

@test "P0-06: load-lessons.sh uses jq or python json encoding, not bare sed" {
  # Static check: the fix must use jq -R -s . OR python3 json.dumps, not just sed
  run grep -E 'jq -R|json\.dumps|json_encode|jq.*rawfile' "$LOAD_LESSONS"
  [[ "$status" -eq 0 ]]
}
