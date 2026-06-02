#!/usr/bin/env bats
# tests/oss/anthropic-skills-delta.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT_DOC="$REPO_ROOT/docs/operational/anthropic-skills-delta-audit.md"
  CUSTOMIZATION_DOC="$REPO_ROOT/docs/operational/customization-patterns.md"
  OP_INDEX="$REPO_ROOT/docs/operational/README.md"
}

@test "anthropic skills delta audit documents upstream sha and no-vendor decision" {
  [[ -f "$AUDIT_DOC" ]]
  grep -Fq "da20c92503b2e8ff1cf28ca81a0df4673debdbf7" "$AUDIT_DOC"
  grep -Fq "No skills are vendored in this pass" "$AUDIT_DOC"
  grep -Fq "Prefer the plugin mechanism" "$AUDIT_DOC"
}

@test "anthropic skills delta audit covers every net-new upstream skill" {
  for skill in \
    claude-api \
    doc-coauthoring \
    frontend-design \
    mcp-builder \
    slack-gif-creator \
    web-artifacts-builder \
    webapp-testing; do
    grep -Fq "$skill" "$AUDIT_DOC"
  done
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
