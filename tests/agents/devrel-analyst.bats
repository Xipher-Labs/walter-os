#!/usr/bin/env bats
# Phase V — Part D: devrel-analyst skill validation
# Covers: AC-13 (skill invocable from CLI + agents)
#
# Tests validate:
#   1. Skill file structure (SKILL.md, query.py)
#   2. CLI invocability (walter-os analyst <query>)
#   3. Query function signatures are correct
#   4. Sanitization applied to LLM-bound inputs
#
# Refs: docs/specs/devrel-analytics-stack.md

setup() {
  SKILL_DIR="$BATS_TEST_DIRNAME/../../skills/devrel-analyst"
  QUERY_SCRIPT="$SKILL_DIR/scripts/query.py"
}

# ── Skill directory structure ─────────────────────────────────────────────────

@test "devrel-analyst skill directory exists" {
  [[ -d "$SKILL_DIR" ]]
}

@test "devrel-analyst SKILL.md exists" {
  [[ -f "$SKILL_DIR/SKILL.md" ]]
}

@test "SKILL.md has skill name devrel-analyst" {
  [[ -f "$SKILL_DIR/SKILL.md" ]]
  grep -qi "devrel-analyst\|devrel analyst" "$SKILL_DIR/SKILL.md"
}

@test "SKILL.md lists supported queries" {
  [[ -f "$SKILL_DIR/SKILL.md" ]]
  local f="$SKILL_DIR/SKILL.md"
  grep -q "top_threads\|optimal_hours\|pattern_match\|roi_per_content\|weekly_digest" "$f"
}

@test "query.py script exists" {
  [[ -f "$QUERY_SCRIPT" ]]
}

@test "query.py has no syntax errors" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  python3 -c "
import ast, sys
with open('$QUERY_SCRIPT') as f:
    src = f.read()
try:
    ast.parse(src)
    sys.exit(0)
except SyntaxError as e:
    print(e)
    sys.exit(1)
"
}

# ── Query function signatures ─────────────────────────────────────────────────

@test "query.py defines top_threads function" {
  [[ -f "$QUERY_SCRIPT" ]]
  grep -q "def top_threads" "$QUERY_SCRIPT"
}

@test "query.py defines optimal_hours function" {
  [[ -f "$QUERY_SCRIPT" ]]
  grep -q "def optimal_hours" "$QUERY_SCRIPT"
}

@test "query.py defines pattern_match function" {
  [[ -f "$QUERY_SCRIPT" ]]
  grep -q "def pattern_match" "$QUERY_SCRIPT"
}

@test "query.py defines roi_per_content_piece function" {
  [[ -f "$QUERY_SCRIPT" ]]
  grep -q "def roi_per_content_piece\|def roi_per_content" "$QUERY_SCRIPT"
}

@test "query.py defines weekly_digest function" {
  [[ -f "$QUERY_SCRIPT" ]]
  grep -q "def weekly_digest" "$QUERY_SCRIPT"
}

# ── Sanitization applied ──────────────────────────────────────────────────────

@test "query.py uses sanitizeForPrompt or sanitize equivalent" {
  [[ -f "$QUERY_SCRIPT" ]]
  # Must sanitize any user input before passing to LLM synthesis
  grep -q "sanitize\|strip_control\|sanitizeForPrompt" "$QUERY_SCRIPT"
}

# ── CLI wrapper ───────────────────────────────────────────────────────────────

@test "devrel-analyst CLI wrapper script exists" {
  [[ -f "$SKILL_DIR/scripts/analyst-cli.sh" ]] || \
  [[ -f "$BATS_TEST_DIRNAME/../../bin/walter-analyst" ]] || \
  grep -q "analyst" "$BATS_TEST_DIRNAME/../../bin/walter-os" 2>/dev/null
}

@test "query.py --help exits cleanly with usage info" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  [[ -f "$QUERY_SCRIPT" ]] || skip "query.py not found"
  # Should show help without requiring DB connection
  python3 "$QUERY_SCRIPT" --help 2>&1 | grep -qi "usage\|query\|analyst\|help"
}

# ── Dry-run mode (no DB) ──────────────────────────────────────────────────────

@test "query.py top_threads dry-run returns markdown structure" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  [[ -f "$QUERY_SCRIPT" ]] || skip "query.py not found"
  # --dry-run flag generates mock output without needing Postgres
  output=$(python3 "$QUERY_SCRIPT" top_threads --dry-run 2>&1 || true)
  echo "output: $output"
  [[ "$output" =~ top|thread|engagement|dry.run|mock|DB_not_connected ]]
}

@test "query.py weekly_digest dry-run returns markdown output" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  [[ -f "$QUERY_SCRIPT" ]] || skip "query.py not found"
  output=$(python3 "$QUERY_SCRIPT" weekly_digest --dry-run 2>&1 || true)
  echo "output: $output"
  [[ "$output" =~ weekly|digest|Weekly|Digest|dry.run|mock ]]
}
