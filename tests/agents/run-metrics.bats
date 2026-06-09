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
  unset WALTER_MODEL_DOMAIN WALTER_MODEL_PHI
  export WALTER_PHI_MODE=0
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

@test "run.sh wires Council model selection through model-selection helper" {
  grep -q "model-router\.sh" "$RUN_SH"
  grep -q "model-selection\.sh" "$RUN_SH"
  grep -q "walter_agent_select_model" "$RUN_SH"
}

@test "run.sh fails closed before sourcing model-selection helper" {
  local guard_line exit_line source_line
  guard_line=$(grep -nF '[[ -r "$LIB_DIR/model-selection.sh" ]]' "$RUN_SH" | head -1 | cut -d: -f1)
  source_line=$(grep -n 'source "$LIB_DIR/model-selection\.sh"' "$RUN_SH" | head -1 | cut -d: -f1)
  exit_line=$(awk -v start="$guard_line" -v end="$source_line" 'NR >= start && NR < end && /exit 3/ { print NR; exit }' "$RUN_SH")

  [[ -n "$guard_line" ]]
  [[ -n "$exit_line" ]]
  [[ -n "$source_line" ]]
  [[ "$guard_line" -lt "$source_line" ]]
  [[ "$exit_line" -lt "$source_line" ]]
}

@test "run.sh fails closed on unreadable model router" {
  grep -qF '[[ -r "$MODEL_ROUTER" ]]' "$RUN_SH"
  grep -q "model router not found or unreadable" "$RUN_SH"
}

@test "run.sh reads Council model routing domain from frontmatter" {
  grep -q "_agent_frontmatter_scalar" "$RUN_SH"
  grep -q '"model_domain"' "$RUN_SH"
  grep -q "frontmatter_domain" "$RUN_SH"
}

@test "run.sh validates and normalizes frontmatter model_domain before routing" {
  grep -q "_agent_model_domain_canonical" "$RUN_SH"
  grep -q "model-domains.tsv" "$RUN_SH"
  grep -q "invalid model_domain" "$RUN_SH"
  grep -q "_agent_legacy_model_domain" "$RUN_SH"
  grep -Fq "tr '[:upper:]-' '[:lower:]_'" "$RUN_SH"
  ! grep -Fq "gsub(" "$RUN_SH"
}

@test "run.sh normalizes CRLF before frontmatter delimiter checks" {
  grep -q 'sub(/\\r$/, "", line)' "$RUN_SH"
  grep -q 'NR == 1 && line == "---"' "$RUN_SH"
  grep -q 'in_frontmatter && line == "---"' "$RUN_SH"
}

@test "run.sh fails closed on duplicate model_domain frontmatter keys" {
  local helper persona
  helper="$(mktemp -t walter-run-helper-XXXXXX)"
  persona="$(mktemp -t walter-agent-persona-XXXXXX)"
  awk '/^_agent_frontmatter_scalar\(\)/,/^}/' "$RUN_SH" > "$helper"
  cat > "$persona" <<'PERSONA'
---
name: duplicate-domain
description: Agent fixture with duplicate routing metadata.
tools: Read
model: router
model_domain: backend_review
model_domain: frontend
---
Body
PERSONA

  run bash -c 'source "$1"; _agent_frontmatter_scalar "$2" model_domain' bash "$helper" "$persona"
  rm -f "$helper" "$persona"

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"duplicate model_domain"* ]]
}

@test "run.sh fails closed on unknown explicit model_domain" {
  local helper persona
  helper="$(mktemp -t walter-run-helper-XXXXXX)"
  persona="$(mktemp -t walter-agent-persona-XXXXXX)"
  awk '
    /^_agent_frontmatter_scalar\(\)/ { emit = 1 }
    emit { print }
    /^_agent_model_domain\(\)/ { in_target = 1 }
    emit && in_target && /^}/ { exit }
  ' "$RUN_SH" > "$helper"
  cat > "$persona" <<'PERSONA'
---
name: invalid-domain
description: Agent fixture with unsupported routing metadata.
tools: Read
model: router
model_domain: typo_domain
---
Body
PERSONA

  run bash -c '
    source "$1"
    AGENT_PERSONA="$2"
    _agent_model_domain reviewer
  ' bash "$helper" "$persona"
  rm -f "$helper" "$persona"

  [[ "$status" -eq 3 ]]
  [[ "$output" == *"invalid model_domain 'typo_domain'"* ]]
  [[ "$output" == *"refusing to run"* ]]
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
  REPO_ROOT="$BATS_TEST_DIRNAME/../.." ruby -ryaml -rdate -e '
    repo = File.expand_path(ENV.fetch("REPO_ROOT"))
    domains_file = File.join(repo, "scripts/walter/lib/model-domains.tsv")
    valid_model_route = lambda do |value|
      !value.nil? &&
        !value.empty? &&
        value.match?(/\A[A-Za-z0-9._\/@:+,\[\]-]+\z/) &&
        value.split(",", -1).all? { |route| !route.empty? }
    end
    allowed = File.readlines(domains_file, chomp: true)
      .map { |line| line.delete_suffix("\r") }
      .reject { |line| line.start_with?("#") || line.strip.empty? }
      .map do |line|
        columns = line.split("\t", 4)
        abort("invalid model domain row: #{line}") if columns.length < 3
        domain, env_key, default_model = columns
        abort("invalid model domain name: #{domain}") unless domain.match?(/\A[a-z][a-z0-9_]*\z/)
        abort("invalid model domain env key: #{env_key}") unless env_key.match?(/\AWALTER_MODEL_[A-Z0-9_]+\z/)
        abort("invalid model domain default: #{default_model.inspect}") if default_model.nil? || default_model.empty?
        abort("invalid model domain default: #{default_model.inspect}") unless valid_model_route.call(default_model)
        domain
      end
    domain_pattern = Regexp.union(allowed).source
    Dir[File.join(repo, "agents/*.md")].each do |path|
      text = File.read(path)
      parts = text.split(/^---\s*$/m, 3)
      abort("#{path}: missing frontmatter") if parts.length < 3 || parts[1].strip.empty?
      data = YAML.safe_load(parts[1], permitted_classes: [Date], aliases: false)
      domain = data["model_domain"]
      abort("#{path}: missing model_domain") unless domain.is_a?(String)
      abort("#{path}: invalid model_domain #{domain.inspect}") unless allowed.include?(domain)
      raw_domains = parts[1].lines.grep(/\A[[:space:]]*model_domain[[:space:]]*:/)
      abort("#{path}: duplicate model_domain keys") unless raw_domains.length == 1
      raw = raw_domains.first
      abort("#{path}: model_domain must be an unquoted scalar") unless raw&.match?(/\A[[:space:]]*model_domain[[:space:]]*:[[:space:]]*(#{domain_pattern})([[:space:]]+#.*)?[[:space:]]*\z/)
    end
  '
}

@test "frontmatter lint rejects duplicate agent model_domain keys" {
  local fixture
  fixture="$BATS_TEST_DIRNAME/../../agents/duplicate-model-domain-test.md"
  cat > "$fixture" <<'AGENT'
---
name: duplicate-model-domain-test
description: Temporary test fixture with duplicate model routing metadata.
tools: Read
model: router
model_domain: backend_review
model_domain: frontend
---
Temporary fixture.
AGENT

  run ruby "$BATS_TEST_DIRNAME/../../tests/lint-frontmatter.rb"
  rm -f "$fixture"

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"duplicate model_domain"* ]]
}

@test "frontmatter lint derives model domains from canonical table" {
  grep -q "model-domains.tsv" "$BATS_TEST_DIRNAME/../../tests/lint-frontmatter.rb"
  ! grep -q "VALID_MODEL_DOMAINS = %w" "$BATS_TEST_DIRNAME/../../tests/lint-frontmatter.rb"
}

@test "frontmatter lint rejects malformed model domain table rows" {
  local domains_file
  domains_file="$(mktemp -t walter-model-domains-XXXXXX)"
  printf 'backend_review\n' > "$domains_file"

  run env WALTER_MODEL_DOMAINS_FILE="$domains_file" ruby "$BATS_TEST_DIRNAME/../../tests/lint-frontmatter.rb"
  rm -f "$domains_file"

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"invalid model domain row"* ]]
}

@test "frontmatter lint reports unreadable model domain table cleanly" {
  local domains_dir
  domains_dir="$(mktemp -d -t walter-model-domains-XXXXXX)"

  run env WALTER_MODEL_DOMAINS_FILE="$domains_dir" ruby "$BATS_TEST_DIRNAME/../../tests/lint-frontmatter.rb"
  rm -rf "$domains_dir"

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"model domain table unreadable"* ]]
  [[ "$output" != *"from "* ]]
}

@test "frontmatter lint rejects empty model domain table" {
  local domains_file
  domains_file="$(mktemp -t walter-model-domains-XXXXXX)"
  printf '# domain\tenv\tdefault\tdescription\n\n' > "$domains_file"

  run env WALTER_MODEL_DOMAINS_FILE="$domains_file" ruby "$BATS_TEST_DIRNAME/../../tests/lint-frontmatter.rb"
  rm -f "$domains_file"

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"model domain table has no valid rows"* ]]
}

@test "frontmatter lint rejects invalid model domain defaults" {
  local domains_file
  domains_file="$(mktemp -t walter-model-domains-XXXXXX)"
  printf 'backend_review\tWALTER_MODEL_BACKEND_REVIEW\tcodex;rm\tBackend review\n' > "$domains_file"

  run env WALTER_MODEL_DOMAINS_FILE="$domains_file" ruby "$BATS_TEST_DIRNAME/../../tests/lint-frontmatter.rb"
  rm -f "$domains_file"

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"invalid model domain default"* ]]
}

@test "frontmatter lint treats empty model domain env as default path" {
  run env WALTER_MODEL_DOMAINS_FILE= ruby "$BATS_TEST_DIRNAME/../../tests/lint-frontmatter.rb"

  [[ "$status" -eq 0 ]]
}

@test "run.sh reports unreadable model domain table distinctly" {
  grep -q "model domain table is missing or unreadable" "$RUN_SH"
}

@test "run.sh fails closed when model domain table is unreadable" {
  grep -q "canonical_status == 2" "$RUN_SH"
  grep -q "invalid model_domain allowlist" "$RUN_SH"
  grep -q "refusing to run" "$RUN_SH"
}

@test "run.sh fails closed when model domain table has no valid rows" {
  local helper domains_file
  helper="$(mktemp -t walter-run-domain-helper-XXXXXX)"
  domains_file="$(mktemp -t walter-model-domains-XXXXXX)"
  awk '/^_agent_model_domain_canonical\(\)/,/^}/' "$RUN_SH" > "$helper"
  cat > "$domains_file" <<'TSV'
# domain	env	default
not a valid row
frontend	WALTER_MODEL_FRONTEND
TSV

  run bash -c '
    source "$1"
    export WALTER_MODEL_DOMAINS_FILE="$2"
    _agent_model_domain_canonical backend_review
  ' bash "$helper" "$domains_file"
  rm -f "$helper" "$domains_file"

  [[ "$status" -eq 2 ]]
  [[ "$output" == *"model domain table has no valid rows"* ]]
}

@test "run.sh rejects model domain rows with invalid defaults" {
  local helper domains_file
  helper="$(mktemp -t walter-run-domain-helper-XXXXXX)"
  domains_file="$(mktemp -t walter-model-domains-XXXXXX)"
  awk '/^_agent_model_domain_canonical\(\)/,/^}/' "$RUN_SH" > "$helper"
  cat > "$domains_file" <<'TSV'
backend_review	WALTER_MODEL_BACKEND_REVIEW	codex;rm	Backend review
TSV

  run bash -c '
    source "$1"
    export WALTER_MODEL_DOMAINS_FILE="$2"
    _agent_model_domain_canonical backend_review
  ' bash "$helper" "$domains_file"
  rm -f "$helper" "$domains_file"

  [[ "$status" -eq 2 ]]
  [[ "$output" == *"model domain table has no valid rows"* ]]
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
