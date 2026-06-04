#!/usr/bin/env bats
# tests/agents/delivery-orchestrator.bats
#
# Covers: docs/specs/delivery-orchestrator.md

setup() {
  command -v ruby >/dev/null 2>&1 || skip "ruby required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AGENT="$REPO_ROOT/agents/delivery-orchestrator.md"
  SPEC="$REPO_ROOT/docs/specs/delivery-orchestrator.md"
  SPEC_INDEX="$REPO_ROOT/docs/specs/README.md"
}

@test "delivery orchestrator agent frontmatter is coordination-only" {
  [[ -f "$AGENT" ]]

  ruby -ryaml -e '
    path = ARGV.fetch(0)
    text = File.read(path)
    frontmatter = text.split(/^---\s*$/, 3).fetch(1)
    data = YAML.safe_load(frontmatter, permitted_classes: [], aliases: false)
    abort "wrong name" unless data["name"] == "delivery-orchestrator"
    abort "missing description" unless data["description"].to_s.include?("coordinate")
    tools = data["tools"].to_s
    %w[Read Grep Glob Bash].each { |tool| abort "missing #{tool}" unless tools.match?(/\b#{tool}\b/) }
    %w[Edit Write].each { |tool| abort "forbidden #{tool}" if tools.match?(/\b#{tool}\b/) }
  ' "$AGENT"
}

@test "delivery orchestrator maps AD-1 roles to existing lanes" {
  [[ -f "$AGENT" ]]

  for role in Product Architect Builder Tester Security Reviewer Release; do
    grep -q "$role" "$AGENT"
  done

  for lane in triage researcher coder reviewer janitor liaison; do
    grep -q "$lane" "$AGENT"
  done
}

@test "delivery orchestrator cannot execute code, self-review, merge, or deploy" {
  [[ -f "$AGENT" ]]

  grep -qi "does not write code" "$AGENT"
  grep -qi "does not review its own diffs" "$AGENT"
  grep -qi "does not merge" "$AGENT"
  grep -qi "does not deploy" "$AGENT"
}

@test "delivery orchestrator fails closed on missing or ambiguous gates" {
  [[ -f "$AGENT" ]]

  grep -qi "fail closed" "$AGENT"
  grep -qi "missing" "$AGENT"
  grep -qi "ambiguous" "$AGENT"
  grep -qi "human" "$AGENT"
}

@test "delivery orchestrator uses feature-state as the pipeline state owner" {
  [[ -f "$AGENT" ]]

  grep -q ".walter/features" "$AGENT"
  grep -q "walter-os feature-state init" "$AGENT"
  grep -q "walter-os feature-state validate" "$AGENT"
}

@test "delivery orchestrator spec is indexed and covers AD-1 acceptance criteria" {
  [[ -f "$SPEC" ]]

  grep -q "delivery-orchestrator.md" "$SPEC_INDEX"
  grep -q "AD-1" "$SPEC"
  grep -q "Role map" "$SPEC"
  grep -q "Fail-closed gates" "$SPEC"
  grep -q "No execution authority" "$SPEC"
  grep -q "Feature-state ownership" "$SPEC"
}
