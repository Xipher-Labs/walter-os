#!/usr/bin/env bats
# Tests for T-2: metrics wiring in scripts/agents/run.sh
# Covers: AC-1 of Improvement 1 (agent_state metric emitted by runner)

setup() {
  RUN_SH="$BATS_TEST_DIRNAME/../../scripts/agents/run.sh"
  METRICS_LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/metrics.sh"
  MODEL_ROUTER_LIB="$BATS_TEST_DIRNAME/../../scripts/walter/lib/model-router.sh"
  [[ -f "$RUN_SH" ]] || skip "run.sh not found"
  [[ -f "$METRICS_LIB" ]] || skip "metrics.sh not found"
  [[ -f "$MODEL_ROUTER_LIB" ]] || skip "model-router.sh not found"

  # Isolated env
  WALTER_METRICS_DIR="$(mktemp -d -t walter-run-metrics-XXXXXX)"
  export WALTER_METRICS_DIR
  export WALTER_METRICS_FILE="$WALTER_METRICS_DIR/metrics.prom"
  export WALTER_METRICS_LOCK="$WALTER_METRICS_FILE.lock"
  export WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.."
  export WALTER_CONFIG="$(mktemp -d -t walter-config-XXXXXX)"
  unset WALTER_MODEL_OVERRIDE WALTER_MODEL_BACKEND_REVIEW WALTER_MODEL_DEFAULT
}

teardown() {
  rm -rf "$WALTER_METRICS_DIR" "$WALTER_CONFIG"
}

@test "run.sh sources metrics.sh (metrics lib is imported)" {
  # Verify metrics.sh is sourced in run.sh
  grep -q "metrics\.sh" "$RUN_SH"
}

@test "run.sh emits walter_council_agent_state metric" {
  # Verify metric_set call for agent_state exists in run.sh
  grep -q "walter_council_agent_state" "$RUN_SH"
}

@test "run.sh emits walter_council_tasks_total at task end" {
  grep -q "walter_council_tasks_total" "$RUN_SH"
}

@test "run.sh emits walter_council_tokens_total at task end" {
  grep -q "walter_council_tokens_total" "$RUN_SH"
}

@test "run.sh sources model-router.sh for Council model selection" {
  grep -q "model-router\.sh" "$RUN_SH"
  grep -q "walter_model_select_primary" "$RUN_SH"
}

@test "run.sh reads Council model routing domain from frontmatter" {
  grep -q "_agent_frontmatter_scalar" "$RUN_SH"
  grep -q '"model_domain"' "$RUN_SH"
  grep -q "frontmatter_domain" "$RUN_SH"
}

@test "run.sh keeps legacy Council agent domain fallback mapping" {
  grep -q "_agent_model_domain" "$RUN_SH"
  grep -q "coder|reviewer|security-auditor" "$RUN_SH"
  grep -q "backend_review" "$RUN_SH"
  grep -q "researcher|triage|architect" "$RUN_SH"
  grep -q "brainstorm" "$RUN_SH"
  grep -q "liaison|tech-writer|devrel-writer" "$RUN_SH"
  grep -q "longform" "$RUN_SH"
}

@test "agent frontmatter declares Walter model routing domains" {
  ruby -ryaml -rdate -e '
    allowed = %w[backend_review frontend longform quick_refactor phi brainstorm default]
    Dir["agents/*.md"].each do |path|
      text = File.read(path)
      match = text.match(/\A---\n(.*?)\n---/m)
      abort("#{path}: missing frontmatter") unless match
      data = YAML.safe_load(match[1], permitted_classes: [Date], aliases: false)
      domain = data["model_domain"]
      abort("#{path}: missing model_domain") unless domain.is_a?(String)
      abort("#{path}: invalid model_domain #{domain.inspect}") unless allowed.include?(domain)
      raw = match[1].lines.grep(/\Amodel_domain: /).first
      abort("#{path}: model_domain must be an unquoted scalar") unless raw&.match?(/\Amodel_domain: (#{allowed.join("|")})\s*\z/)
    end
  '
}

@test "run.sh does not hardcode primary Council models" {
  ! grep -q 'MODEL="haiku"' "$RUN_SH"
  ! grep -q 'MODEL="sonnet"' "$RUN_SH"
  ! grep -q 'llm_invoke "$AGENT" "haiku"' "$RUN_SH"
}

@test "run.sh emits walter_council_heartbeat_age_seconds" {
  grep -q "walter_council_heartbeat_age_seconds" "$RUN_SH"
}

@test "R3: heartbeat loop updates walter_council_heartbeat_age_seconds (not just at init)" {
  # The metric must be updated inside the background heartbeat loop body,
  # not only at the start/end of the run. Check that metric_set for
  # heartbeat_age_seconds appears within the while-sleep loop block.
  # Strategy: extract the while-loop region and grep for metric_set there.
  local loop_body
  loop_body=$(awk '/while sleep.*_hb_interval/,/done/' "$RUN_SH")
  echo "$loop_body" | grep -q "heartbeat_age_seconds"
}

@test "run.sh reads token count from OUTFILE_RAW not OUTFILE (T-2 follow-up)" {
  # run.sh must reference OUTFILE_RAW when extracting usage.total_tokens.
  # OUTFILE contains extracted text (post-jq); raw JSON is in OUTFILE_RAW.
  grep -q "OUTFILE_RAW" "$RUN_SH"
}

@test "llm.sh writes raw JSON to WALTER_LLM_RAW_FILE when set" {
  LLM_LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/llm.sh"
  [[ -f "$LLM_LIB" ]] || skip "llm.sh not found"
  grep -q "WALTER_LLM_RAW_FILE" "$LLM_LIB"
}

@test "run.sh contains cleanup_metrics trap to reset agent_state on early exit" {
  # RED: verify the fix is present in run.sh — cleanup_metrics function + trap EXIT
  # that resets agent_state to 0 when _AGENT_TASK_OK is still 0.
  # Before the fix: agent_state is set to 1 before claim with no reset on failure.
  # After the fix: an EXIT trap calls cleanup_metrics which resets to 0.
  grep -q "_AGENT_TASK_OK" "$RUN_SH"
  grep -q "cleanup_metrics" "$RUN_SH"
}

@test "token extraction: OUTFILE_RAW JSON usage.total_tokens appears in metrics (behavioral)" {
  # Behavioral test for the OUTFILE_RAW extraction path in run.sh lines 308-314.
  # We replicate the logic directly (not grep-against-source) and verify the
  # metric is written correctly.

  # Source metrics lib
  # shellcheck source=/dev/null
  source "$METRICS_LIB"
  metrics_init

  # Create a fake raw API response (same structure as OpenAI/Claude API)
  OUTFILE_RAW="$(mktemp -t walter-test-raw.XXXXXX)"
  printf '{"choices":[{"message":{"content":"hello"}}],"usage":{"prompt_tokens":100,"completion_tokens":200,"total_tokens":1234}}\n' \
    > "$OUTFILE_RAW"

  # Replicate the exact token extraction + metric_inc from run.sh §metrics: task end
  AGENT="test-agent"
  MODEL="sonnet"
  TOKENS_USED=$(jq -r '.usage.total_tokens // 0' "$OUTFILE_RAW" 2>/dev/null || echo 0)
  TOKENS_USED="${TOKENS_USED:-0}"
  if [[ "$TOKENS_USED" -gt 0 ]]; then
    metric_inc "walter_council_tokens_total" "agent=\"${AGENT}\",model=\"${MODEL}\"" "$TOKENS_USED"
  fi

  rm -f "$OUTFILE_RAW"

  # Assert: the metrics file contains the expected counter value (1234)
  [[ -f "$WALTER_METRICS_FILE" ]]
  grep -qF 'walter_council_tokens_total{agent="test-agent",model="sonnet"} 1234' "$WALTER_METRICS_FILE"
}

@test "token metrics use routed model value" {
  # Source metrics and router libs.
  # shellcheck source=/dev/null
  source "$METRICS_LIB"
  # shellcheck source=/dev/null
  source "$MODEL_ROUTER_LIB"
  metrics_init

  OUTFILE_RAW="$(mktemp -t walter-test-raw.XXXXXX)"
  printf '{"usage":{"total_tokens":1234}}\n' > "$OUTFILE_RAW"

  AGENT="reviewer"
  MODEL=""
  export WALTER_MODEL_BACKEND_REVIEW="codex-pro"
  walter_model_select_primary backend_review MODEL
  TOKENS_USED=$(jq -r '.usage.total_tokens // 0' "$OUTFILE_RAW" 2>/dev/null || echo 0)
  TOKENS_USED="${TOKENS_USED:-0}"
  if [[ "$TOKENS_USED" -gt 0 ]]; then
    metric_inc "walter_council_tokens_total" "agent=\"${AGENT}\",model=\"${MODEL}\"" "$TOKENS_USED"
  fi

  rm -f "$OUTFILE_RAW"

  grep -qF 'walter_council_tokens_total{agent="reviewer",model="codex-pro"} 1234' "$WALTER_METRICS_FILE"
}

# ---- M1: trap consolidation — lesson runner trap must not overwrite main cleanup ----

@test "run.sh uses a single consolidated EXIT trap (M1)" {
  # Static analysis: run.sh must NOT have multiple bare 'trap ... EXIT' calls.
  # The fix consolidates all cleanup into _run_cleanup() with one trap call.
  # Count trap ... EXIT assignments:
  local trap_count
  trap_count=$(grep -c "^trap '.*' EXIT" "$RUN_SH" || true)
  # Should be exactly 1 (the consolidated _run_cleanup trap)
  [[ "$trap_count" -eq 1 ]]
}

@test "run.sh _run_cleanup references lesson runner tempfile (M1)" {
  # The consolidated cleanup must include _LESSON_EXTRACT_RUNNER so it is
  # cleaned up even if the lesson extraction section exits early.
  grep -q "_LESSON_EXTRACT_RUNNER" "$RUN_SH"
  # And it must appear in the _run_cleanup function body
  grep -A5 "_run_cleanup" "$RUN_SH" | grep -q "_LESSON_EXTRACT_RUNNER"
}

@test "run.sh uses mktemp for claim error file (no /tmp/claim.err hardcoded)" {
  # Fix 4: concurrent agents clobber each other's /tmp/claim.err.
  # After the fix, run.sh must NOT reference the hardcoded /tmp/claim.err path.
  ! grep -q '2>/tmp/claim\.err' "$RUN_SH"
  ! grep -q '/tmp/claim\.err' "$RUN_SH"
}
