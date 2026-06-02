#!/usr/bin/env bats
# tests/oss/anthropic-skills-delta.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT_DOC="$REPO_ROOT/docs/operational/anthropic-skills-delta-audit.md"
  CUSTOMIZATION_DOC="$REPO_ROOT/docs/operational/customization-patterns.md"
  OP_INDEX="$REPO_ROOT/docs/operational/README.md"
}

assert_decision_row() {
  local skill="$1"
  local decision_prefix="$2"

  grep -Fq "| \`$skill\` | No | $decision_prefix" "$AUDIT_DOC"
}

@test "anthropic skills delta audit documents upstream sha and no-vendor decision" {
  [[ -f "$AUDIT_DOC" ]]
  grep -Fq "da20c92503b2e8ff1cf28ca81a0df4673debdbf7" "$AUDIT_DOC"
  grep -Fq "No skills are vendored in this pass" "$AUDIT_DOC"
  grep -Fq "Prefer the plugin mechanism" "$AUDIT_DOC"
}

@test "anthropic skills delta audit covers every net-new upstream skill" {
  assert_decision_row "claude-api" "Skip "
  assert_decision_row "doc-coauthoring" "Skip "
  assert_decision_row "frontend-design" "Skip "
  assert_decision_row "mcp-builder" "Track "
  assert_decision_row "slack-gif-creator" "Skip"
  assert_decision_row "web-artifacts-builder" "Skip "
  assert_decision_row "webapp-testing" "Track "
}

@test "anthropic skills delta audit flags stale issue plugin entries" {
  grep -Fq "consolidate-memory" "$AUDIT_DOC"
  grep -Fq "setup-cowork" "$AUDIT_DOC"
  grep -Fq "stale issue data" "$AUDIT_DOC"
}

@test "anthropic skills docs avoid broken local anthropic-skills paths" {
  if grep -Fq "skills/anthropic-skills" "$CUSTOMIZATION_DOC"; then
    return 1
  fi
  grep -Fq "anthropic-skills:skill-creator" "$CUSTOMIZATION_DOC"
}

@test "operational index links the delta audit" {
  grep -Fq "anthropic-skills-delta-audit.md" "$OP_INDEX"
}
