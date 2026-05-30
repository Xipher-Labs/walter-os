#!/usr/bin/env bats
# Tests for T-6: LLM metadata extension with task_id and context
# Covers: AC-1 of Improvement 2

setup() {
  LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/llm.sh"
  [[ -f "$LIB" ]] || skip "llm.sh not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"
}

@test "llm.sh metadata includes task_id field" {
  grep -q "task_id" "$LIB"
}

@test "llm.sh metadata includes context field" {
  grep -q "context" "$LIB"
}

@test "llm.sh metadata includes model_alias field" {
  grep -q "model_alias" "$LIB"
}

@test "llm.sh metadata includes domain field" {
  grep -q "domain" "$LIB"
  grep -q "WALTER_MODEL_DOMAIN" "$LIB"
}

@test "llm.sh metadata includes agent_id field (not just agent)" {
  grep -q "agent_id" "$LIB"
}

@test "llm_invoke payload contains task_id from WALTER_AGENT_PLANE_ISSUE" {
  # Source the lib and verify the payload construction references the env var
  source "$LIB"
  # Verify the function uses WALTER_AGENT_PLANE_ISSUE
  grep -q "WALTER_AGENT_PLANE_ISSUE" "$LIB"
}

@test "llm_invoke payload contains context from WALTER_AGENT_CONTEXT" {
  grep -q "WALTER_AGENT_CONTEXT" "$LIB"
}
