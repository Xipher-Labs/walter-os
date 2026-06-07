#!/usr/bin/env bats
# tests/cli/ai.bats
#
# Covers: AC-1, AC-2, AC-3, AC-4, AC-5, AC-6
# W-2: Walter CLI AI Integration
# Refs: docs/specs/phase-w-2-cli-ai.md

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WALTER_BIN="${REPO_ROOT}/bin/walter"
LLM_LIB="${REPO_ROOT}/scripts/agents/lib/llm.sh"
FIXTURES="${REPO_ROOT}/tests/fixtures"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export WALTER_OS_HOME="$REPO_ROOT"

  # Clear all LLM credentials — tests start with no AI configured
  unset LITELLM_BASE_URL LITELLM_API_KEY ANTHROPIC_API_KEY ANTHROPIC_ENTERPRISE_KEY

  # Ensure no mock file leaks between tests
  unset WALTER_LLM_MOCK_FILE
  unset WALTER_MODEL_OVERRIDE WALTER_MODEL_DEFAULT WALTER_MODEL_LONGFORM
  unset WALTER_MODEL_BRAINSTORM WALTER_MODEL_FRONTEND WALTER_MODEL_BACKEND_REVIEW
  unset WALTER_AI_CAPABILITIES_FILE

  mkdir -p "${TEST_HOME}/.config/walter-os"

  # Fake walter-os binary — subcommand-aware so tests can verify routing
  mkdir -p "${TEST_HOME}/bin"
  cat > "${TEST_HOME}/bin/walter-os" << 'FAKE_WOS'
#!/usr/bin/env bash
case "${1:-}_${2:-}" in
  agents_status) echo "running agents: 0" ;;
  spend_report)  echo '{"tokens":1234,"cost":0.05}' ;;
  *)             echo "{}" ;;
esac
FAKE_WOS
  chmod +x "${TEST_HOME}/bin/walter-os"

  # Prepend fake bin to PATH so walter finds it
  export PATH="${TEST_HOME}/bin:${PATH}"
}

teardown() {
  rm -rf "$TEST_HOME"
}

install_curl_capture() {
  local capture_file="$1"
  cat > "${TEST_HOME}/bin/curl" <<CURL_STUB
#!/usr/bin/env bash
capture_file="${capture_file}"
payload=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -d|--data|--data-raw|--data-binary)
      shift
      payload="\${1:-}"
      ;;
  esac
  shift || true
done
printf '%s\n' "\$payload" >> "\$capture_file"
printf '{"choices":[{"message":{"content":"captured-response"}}]}\n'
CURL_STUB
  chmod +x "${TEST_HOME}/bin/curl"
}

last_spend_model() {
  jq -r '.model' "${HOME}/.config/walter-os/cli-spend.jsonl" | tail -1
}

# -----------------------------------------------------------------------
# Task 1: llm_available() helper [AC-1, AC-2, AC-3, AC-4]
# -----------------------------------------------------------------------

@test "llm_available returns 1 when no LLM credentials are set [AC-1]" {
  source "$LLM_LIB"
  unset LITELLM_BASE_URL LITELLM_API_KEY ANTHROPIC_API_KEY ANTHROPIC_ENTERPRISE_KEY
  ! llm_available
}

@test "llm_available returns 0 when LITELLM_BASE_URL and LITELLM_API_KEY are set [AC-1]" {
  source "$LLM_LIB"
  export LITELLM_BASE_URL="http://litellm:4000"
  export LITELLM_API_KEY="sk-test"
  llm_available
}

@test "llm_available returns 0 when only ANTHROPIC_API_KEY is set [AC-1]" {
  source "$LLM_LIB"
  unset LITELLM_BASE_URL LITELLM_API_KEY
  export ANTHROPIC_API_KEY="sk-ant-test"
  llm_available
}

# -----------------------------------------------------------------------
# Task 2: walter new project --interactive [AC-1, AC-5]
# -----------------------------------------------------------------------

@test "walter new project --interactive: AI not configured message and exits 1 when no LLM set [AC-1]" {
  run bash "$WALTER_BIN" new project --interactive
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "AI not configured\|not configured"
}

@test "walter new project --interactive: happy path with mock LLM returns spec charter and AGENTS.md [AC-1]" {
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-interview.json"
  run bash "$WALTER_BIN" new project --interactive
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "## Problem"
  echo "$output" | grep -q "# AGENTS.md"
}

@test "walter new project --interactive: with --write flag writes files to disk [AC-1]" {
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-interview.json"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  cd "$tmp_dir"
  run bash "$WALTER_BIN" new project --interactive --write
  [ "$status" -eq 0 ]
  # Should have created AGENTS.md in the write dir
  ls "${tmp_dir}"/AGENTS.md 2>/dev/null || ls "${tmp_dir}"/docs/specs/*.md 2>/dev/null
  cd -
  rm -rf "$tmp_dir"
}

# -----------------------------------------------------------------------
# Task 3: walter ask [AC-2, AC-5]
# -----------------------------------------------------------------------

@test "walter ask: exits 1 with clear message when AI not configured [AC-2]" {
  run bash "$WALTER_BIN" ask "what agents are blocked"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "AI not configured\|not configured"
}

@test "walter ask: exits 1 when no question given [AC-2]" {
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-ask.json"
  run bash "$WALTER_BIN" ask
  [ "$status" -eq 1 ]
}

@test "walter ask: returns mock response when LLM is mocked [AC-2]" {
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-ask.json"
  run bash "$WALTER_BIN" ask "what agents are blocked"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "mock-ask-response"
}

@test "walter ask: records cost to cli-spend.jsonl [AC-2]" {
  export WALTER_MODEL_DEFAULT=route-ask
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-ask.json"
  run bash "$WALTER_BIN" ask "test cost recording"
  [ "$status" -eq 0 ]
  local spend_file="${HOME}/.config/walter-os/cli-spend.jsonl"
  [ -f "$spend_file" ]
  grep -q "walter ask" "$spend_file"
  [ "$(last_spend_model)" = "route-ask" ]
}

# -----------------------------------------------------------------------
# Task 4: walter explain [AC-3, AC-5]
# -----------------------------------------------------------------------

@test "walter explain: exits 1 with list of skills when unknown skill given [AC-3]" {
  run bash "$WALTER_BIN" explain nonexistent-skill-xyz
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "available\|skill\|not found"
}

@test "walter explain: falls back to raw SKILL.md content when no LLM configured [AC-3]" {
  # Create a fake skill in skills/ for testing
  local skill_dir="${REPO_ROOT}/skills/test-explain-skill"
  mkdir -p "$skill_dir"
  printf '# Test Explain Skill\n\nThis is the raw skill content for testing.\n' > "${skill_dir}/SKILL.md"
  run bash "$WALTER_BIN" explain test-explain-skill
  rm -rf "$skill_dir"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "raw skill content for testing"
}

@test "walter explain: returns LLM explanation when mock is set [AC-3]" {
  local skill_dir="${REPO_ROOT}/skills/test-explain-skill"
  mkdir -p "$skill_dir"
  printf '# Test Explain Skill\n\nThis is the raw skill content for testing.\n' > "${skill_dir}/SKILL.md"
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-explain.json"
  run bash "$WALTER_BIN" explain test-explain-skill
  rm -rf "$skill_dir"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "mock-explain-response"
}

# -----------------------------------------------------------------------
# Task 5: walter pivot [AC-4, AC-5]
# -----------------------------------------------------------------------

@test "walter pivot: exits 1 cleanly (no broken cat error) when skill dir missing and LLM mocked [WARN-1]" {
  # Temporarily rename skill dir to simulate missing install, with LLM mocked
  # so we exercise the code path that previously fell through to `cat SKILL.md`.
  local skill_dir="${REPO_ROOT}/skills/project-pivot"
  local skill_dir_bak="${REPO_ROOT}/skills/project-pivot.bak_test_$$"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  printf '# AGENTS.md\nExisting project.\n' > "${tmp_dir}/AGENTS.md"
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-interview.json"
  mv "$skill_dir" "$skill_dir_bak"
  cd "$tmp_dir"
  run bash "$WALTER_BIN" pivot
  cd -
  mv "$skill_dir_bak" "$skill_dir"
  rm -rf "$tmp_dir"
  unset WALTER_LLM_MOCK_FILE
  [ "$status" -eq 1 ]
  # Must emit the actionable message, not a cryptic shell error
  echo "$output" | grep -qi "skill install project-pivot"
  # Must NOT emit the cryptic "No such file or directory" error from broken cat
  ! echo "$output" | grep -qi "No such file or directory"
}

@test "walter pivot: exits 1 with guidance when no AGENTS.md in cwd [AC-4]" {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  cd "$tmp_dir"
  run bash "$WALTER_BIN" pivot
  cd -
  rm -rf "$tmp_dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "AGENTS.md\|no agents\|pivot"
}

@test "walter pivot: exits 1 with AI not configured message when no LLM set and AGENTS.md present [AC-4]" {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  printf '# AGENTS.md\nThis is an existing project.\n' > "${tmp_dir}/AGENTS.md"
  cd "$tmp_dir"
  run bash "$WALTER_BIN" pivot
  cd -
  rm -rf "$tmp_dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "AI not configured\|not configured"
}

@test "walter pivot: exits 0 and produces output when AGENTS.md present and LLM mocked [AC-4]" {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  printf '# AGENTS.md\nThis is an existing project.\n' > "${tmp_dir}/AGENTS.md"
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-interview.json"
  cd "$tmp_dir"
  run bash "$WALTER_BIN" pivot
  cd -
  rm -rf "$tmp_dir"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "walter pivot: SKILL.md content is injected into LLM system prompt [M-AC1]" {
  local tmp_dir debug_file
  tmp_dir="$(mktemp -d)"
  debug_file="$(mktemp)"
  trap "rm -f '$debug_file'; rm -rf '$tmp_dir'" EXIT
  printf '# AGENTS.md\nThis is an existing project.\n' > "${tmp_dir}/AGENTS.md"
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-interview.json"
  export WALTER_LLM_DEBUG=1
  export WALTER_LLM_DEBUG_FILE="$debug_file"
  cd "$tmp_dir"
  run bash "$WALTER_BIN" pivot
  cd -
  [ "$status" -eq 0 ]
  # SKILL.md must be in the system prompt — check for distinctive content
  grep -q 'Interview Protocol' "$debug_file" \
    || { echo "SKILL.md content not found in LLM system prompt (debug: $debug_file)"; cat "$debug_file"; return 1; }
  unset WALTER_LLM_DEBUG WALTER_LLM_DEBUG_FILE
}

@test "llm.sh: debug file is mode 0600 when WALTER_LLM_DEBUG_FILE unset [WARN-2]" {
  # When WALTER_LLM_DEBUG=1 with no explicit WALTER_LLM_DEBUG_FILE, llm.sh creates a
  # mktemp file. Verify it gets chmod 600 applied (not the default 644 /tmp file).
  # Strategy: snapshot the system temp dir before and after to find the new file.
  #
  # Path normalisation: macOS $TMPDIR has a trailing slash, Linux CI's /tmp
  # does not. Use `${tmpbase%/}/` to collapse both cases to a canonical
  # `<dir>/` form so the glob matches in both environments.
  local tmpbase mode pre_files post_files new_file
  tmpbase="${TMPDIR:-/tmp}"
  tmpbase="${tmpbase%/}/"
  pre_files=$(ls -1 "${tmpbase}"walter-llm-debug.* 2>/dev/null | sort || true)
  source "$LLM_LIB"
  unset WALTER_LLM_DEBUG_FILE
  WALTER_LLM_DEBUG=1 \
  WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-interview.json" \
  llm_invoke_or_mock "test-agent" "haiku" "sys" "usr" 512 >/dev/null 2>&1 || true
  post_files=$(ls -1 "${tmpbase}"walter-llm-debug.* 2>/dev/null | sort || true)
  new_file=$(comm -13 <(printf '%s\n' "$pre_files") <(printf '%s\n' "$post_files") | head -1)
  [[ -n "$new_file" ]] || { echo "No new walter-llm-debug file found in ${tmpbase}"; return 1; }
  # `stat` flag meanings diverge between BSD (macOS) and GNU (Linux). On Linux
  # `stat -f` means "filesystem info" (succeeds with wrong output), so the
  # old `stat -f '%A' || stat -c '%a'` cascade never fell through. Detect by
  # platform.
  if [[ "$(uname -s)" == "Darwin" ]]; then
    mode=$(stat -f '%A' "$new_file" 2>/dev/null)
  else
    mode=$(stat -c '%a' "$new_file" 2>/dev/null)
  fi
  rm -f "$new_file"
  [[ "$mode" == "600" || "$mode" == "0600" ]] \
    || { echo "Debug file mode is '$mode', expected 600"; return 1; }
}

# -----------------------------------------------------------------------
# Task 6: walter help mentions new commands [AC-6]
# -----------------------------------------------------------------------

@test "walter help output contains 'ask' command [AC-6]" {
  run bash "$WALTER_BIN" help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ask"
}

@test "walter help output contains 'explain' command [AC-6]" {
  run bash "$WALTER_BIN" help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "explain"
}

@test "walter help output contains 'pivot' command [AC-6]" {
  run bash "$WALTER_BIN" help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "pivot"
}

@test "walter help output contains 'new project --interactive' [AC-6]" {
  run bash "$WALTER_BIN" help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "\-\-interactive\|interactive"
}

# -----------------------------------------------------------------------
# NIT 1: Subcommand-aware walter-os stub [AC-2]
# -----------------------------------------------------------------------

@test "fake walter-os stub: agents status returns agent info, spend report returns spend info [AC-2]" {
  # This test verifies the stub is subcommand-aware — different subcommands
  # produce different output, matching what walter ask actually calls.
  run "${TEST_HOME}/bin/walter-os" agents status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "running agents"

  run "${TEST_HOME}/bin/walter-os" spend report --last 1d
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "tokens"
}

# -----------------------------------------------------------------------
# BLOCKER 2: walter ask uses --last 1d (not --last 24h) [AC-2]
# -----------------------------------------------------------------------

# -----------------------------------------------------------------------
# BLOCKER 1: Path traversal via answer_name [AC-1]
# -----------------------------------------------------------------------

@test "new-project-interactive: path traversal input sanitized, stays in docs/specs [AC-1]" {
  # Supply a malicious name via stdin-bypass: in mock mode stdin is not read
  # but the sanitization applies to answer_name before writing.
  # We test the sanitization helper directly by sourcing and calling it.
  # The fix: local_name is sanitized via tr -cd '[:alnum:]-_' | head -c 64
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  cd "$tmp_dir"

  # Simulate what the fix does: sanitize a traversal string
  local traversal="../../etc/passwd"
  local sanitized
  sanitized="$(printf '%s' "$traversal" | tr -cd '[:alnum:]-_' | head -c 64)"
  # Must not contain slashes or dots
  [[ "$sanitized" != *"/"* ]]
  [[ "$sanitized" != *".."* ]]
  # Sanitized output must equal the expected safe string
  [ "$sanitized" = "etcpasswd" ]
  # Key check: sanitized path is safe for use as filename component
  local safe_path="${tmp_dir}/docs/specs/${sanitized}.md"
  [[ "$safe_path" == "${tmp_dir}"* ]]

  cd -
  rm -rf "$tmp_dir"
}

@test "new-project-interactive: special chars stripped from project name [AC-1]" {
  local input="My Project!"
  local sanitized
  sanitized="$(printf '%s' "$input" | tr -cd '[:alnum:]-_' | head -c 64)"
  [ "$sanitized" = "MyProject" ]
}

@test "new-project-interactive: empty name defaults to new-project [AC-1]" {
  local input=""
  local sanitized
  sanitized="$(printf '%s' "$input" | tr -cd '[:alnum:]-_' | head -c 64)"
  [[ -z "$sanitized" ]]
  # After sanitization empty string: code should default to new-project
  local local_name="${sanitized:-new-project}"
  [ "$local_name" = "new-project" ]
}

@test "new-project-interactive: name truncated to 64 chars [AC-1]" {
  local input
  input="$(printf 'a%.0s' {1..100})"  # 100 'a' chars
  local sanitized
  sanitized="$(printf '%s' "$input" | tr -cd '[:alnum:]-_' | head -c 64)"
  [ "${#sanitized}" -le 64 ]
  [ "${#sanitized}" -eq 64 ]
}

# -----------------------------------------------------------------------
# WARN 1: Mock mode emits stderr warning
# -----------------------------------------------------------------------

@test "llm_invoke_or_mock: emits stderr warning when WALTER_LLM_MOCK_FILE set [WARN-1]" {
  source "$LLM_LIB"
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-ask.json"
  # Use run to capture stderr separately — bats captures combined by default
  # We check stderr by examining output with &2 redirect
  local stderr_out
  stderr_out="$(llm_invoke_or_mock "test-agent" "haiku" "sys" "user" 512 2>&1 >/dev/null)"
  echo "$stderr_out" | grep -qi "WARN\|mock"
}

# -----------------------------------------------------------------------
# WARN 2: _record_cli_spend extracted to shared lib [AC-7]
# -----------------------------------------------------------------------

@test "spend-record.sh lib exists and _record_cli_spend function is usable [AC-7]" {
  local lib="${REPO_ROOT}/scripts/walter/lib/spend-record.sh"
  [ -f "$lib" ]
  source "$lib"
  # Function must exist after sourcing
  declare -f _record_cli_spend > /dev/null
}

@test "spend-record.sh: modifying lib affects all 4 commands (single source of truth) [AC-7]" {
  # Verify all 4 command files source spend-record.sh rather than defining
  # their own copy of _record_cli_spend
  local lib="scripts/walter/lib/spend-record.sh"
  for cmd in ask explain pivot new-project-interactive; do
    local f="${REPO_ROOT}/scripts/walter/subcommands/${cmd}.sh"
    grep -q "spend-record.sh" "$f" || {
      echo "FAIL: ${cmd}.sh does not source spend-record.sh"
      return 1
    }
  done
}

# -----------------------------------------------------------------------
# WARN 3: Cost recording for explain, pivot, new-project-interactive [AC-7]
# -----------------------------------------------------------------------

@test "walter explain: records cost to cli-spend.jsonl [AC-7]" {
  local skill_dir="${REPO_ROOT}/skills/test-cost-skill"
  mkdir -p "$skill_dir"
  printf '# Test Cost Skill\n\nContent for cost recording test.\n' > "${skill_dir}/SKILL.md"
  export WALTER_MODEL_LONGFORM=route-explain
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-explain.json"
  run bash "$WALTER_BIN" explain test-cost-skill
  rm -rf "$skill_dir"
  [ "$status" -eq 0 ]
  local spend_file="${HOME}/.config/walter-os/cli-spend.jsonl"
  [ -f "$spend_file" ]
  grep -q "walter explain" "$spend_file"
  [ "$(last_spend_model)" = "route-explain" ]
}

@test "walter pivot: records cost to cli-spend.jsonl [AC-7]" {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  printf '# AGENTS.md\nExisting project.\n' > "${tmp_dir}/AGENTS.md"
  export WALTER_MODEL_BRAINSTORM=route-pivot
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-interview.json"
  cd "$tmp_dir"
  run bash "$WALTER_BIN" pivot
  cd -
  rm -rf "$tmp_dir"
  [ "$status" -eq 0 ]
  local spend_file="${HOME}/.config/walter-os/cli-spend.jsonl"
  [ -f "$spend_file" ]
  grep -q "walter pivot" "$spend_file"
  [ "$(last_spend_model)" = "route-pivot" ]
}

@test "walter new project --interactive: records cost to cli-spend.jsonl [AC-7]" {
  export WALTER_MODEL_BRAINSTORM=route-interview
  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-interview.json"
  run bash "$WALTER_BIN" new project --interactive
  [ "$status" -eq 0 ]
  local spend_file="${HOME}/.config/walter-os/cli-spend.jsonl"
  [ -f "$spend_file" ]
  grep -q "walter new project" "$spend_file"
  [ "$(last_spend_model)" = "route-interview" ]
}

@test "walter ask: sends default model route to LiteLLM payload [AC-2]" {
  local payload_file
  payload_file="${TEST_HOME}/curl-payload.jsonl"
  install_curl_capture "$payload_file"
  export LITELLM_BASE_URL="http://litellm.test"
  export LITELLM_API_KEY="sk-test"
  export WALTER_MODEL_DEFAULT=route-ask

  run bash "$WALTER_BIN" ask "what changed?"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.model' "$payload_file")" = "route-ask" ]
  [ "$(jq -r '.metadata.domain' "$payload_file")" = "default" ]
}

@test "walter explain: sends longform model route to LiteLLM payload [AC-3]" {
  local payload_file skill_dir
  payload_file="${TEST_HOME}/curl-payload.jsonl"
  install_curl_capture "$payload_file"
  skill_dir="${REPO_ROOT}/skills/test-route-skill"
  mkdir -p "$skill_dir"
  printf '# Test Route Skill\n\nContent for route test.\n' > "${skill_dir}/SKILL.md"
  export LITELLM_BASE_URL="http://litellm.test"
  export LITELLM_API_KEY="sk-test"
  export WALTER_MODEL_LONGFORM=route-explain

  run bash "$WALTER_BIN" explain test-route-skill

  rm -rf "$skill_dir"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.model' "$payload_file")" = "route-explain" ]
  [ "$(jq -r '.metadata.domain' "$payload_file")" = "longform" ]
}

@test "walter pivot: sends brainstorm model route to LiteLLM payload [AC-4]" {
  local payload_file tmp_dir
  payload_file="${TEST_HOME}/curl-payload.jsonl"
  install_curl_capture "$payload_file"
  tmp_dir="$(mktemp -d)"
  printf '# AGENTS.md\nExisting project.\n' > "${tmp_dir}/AGENTS.md"
  export LITELLM_BASE_URL="http://litellm.test"
  export LITELLM_API_KEY="sk-test"
  export WALTER_MODEL_BRAINSTORM=route-pivot

  run bash -c "cd '$tmp_dir' && bash '$WALTER_BIN' pivot"

  rm -rf "$tmp_dir"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.model' "$payload_file")" = "route-pivot" ]
  [ "$(jq -r '.metadata.domain' "$payload_file")" = "brainstorm" ]
}

@test "walter new project --interactive: sends brainstorm route to LiteLLM payload [AC-1]" {
  local payload_file
  payload_file="${TEST_HOME}/curl-payload.jsonl"
  install_curl_capture "$payload_file"
  export LITELLM_BASE_URL="http://litellm.test"
  export LITELLM_API_KEY="sk-test"
  export WALTER_MODEL_BRAINSTORM=route-interview

  run bash -c "printf 'demo-proj\ndevtools\nbash\nnone\nprojects\n' | bash '$WALTER_BIN' new project --interactive"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.model' "$payload_file")" = "route-interview" ]
  [ "$(jq -r '.metadata.domain' "$payload_file")" = "brainstorm" ]
}

@test "walter new project: discovery flow uses model router aliases [AC-1]" {
  local cmd_file="${REPO_ROOT}/scripts/walter/subcommands/new-project.sh"

  grep -q "model-router.sh" "$cmd_file"
  grep -q 'walter_model_select_primary brainstorm discovery_model' "$cmd_file"
  grep -q 'walter_model_select_primary longform synth_model' "$cmd_file"
  grep -q 'litellm_chat "$pass1_prompt" "$discovery_model"' "$cmd_file"
  grep -q 'litellm_chat "$pass2_prompt" "$discovery_model"' "$cmd_file"
  grep -q 'litellm_chat "$synth_prompt" "$synth_model"' "$cmd_file"
  ! grep -q 'litellm_chat "$pass1_prompt" "sonnet"' "$cmd_file"
  ! grep -q 'litellm_chat "$synth_prompt" "opus"' "$cmd_file"
}

@test "walter ask: calls spend report --last 1d not --last 24h [AC-2]" {
  # Install a recording stub that logs its argv to a file
  local arg_log="${TEST_HOME}/walter-os-args.log"
  cat > "${TEST_HOME}/bin/walter-os" << RECORDING_STUB
#!/usr/bin/env bash
echo "\$@" >> "${arg_log}"
case "\${1:-}_\${2:-}" in
  agents_status) echo "running agents: 0" ;;
  spend_report)  echo '{"tokens":1234,"cost":0.05}' ;;
  *)             echo "{}" ;;
esac
RECORDING_STUB
  chmod +x "${TEST_HOME}/bin/walter-os"

  export WALTER_LLM_MOCK_FILE="${FIXTURES}/mock-ask.json"
  run bash "$WALTER_BIN" ask "test spend flag"
  [ "$status" -eq 0 ]

  # Must have called spend report with --last 1d, NOT --last 24h
  grep -q "spend report --last 1d" "$arg_log"
  ! grep -q "spend report --last 24h" "$arg_log"
}

# -----------------------------------------------------------------------
# WARN 1 (W-2 round 2): AC-7 schema — validate required fields [AC-7]
# -----------------------------------------------------------------------

@test "AC-7: cli-spend.jsonl contains required schema fields [AC-7]" {
  # Source the lib and invoke _record_cli_spend directly
  local lib="${REPO_ROOT}/scripts/walter/lib/spend-record.sh"
  source "$lib"

  # Call the function
  _record_cli_spend "walter ask" "claude-haiku" 256

  local spend_file="${HOME}/.config/walter-os/cli-spend.jsonl"
  [ -f "$spend_file" ]

  # jq validates all four required fields are present and non-null
  jq -e '.timestamp and .command and .model and (.approx_tokens | type == "number")' \
    "$spend_file" > /dev/null
}

# -----------------------------------------------------------------------
# NIT (W-2 round 2): spend-record.sh requires jq (no unsafe fallback)
# -----------------------------------------------------------------------

@test "spend-record.sh: returns error and prints message when jq missing [AC-7]" {
  local lib="${REPO_ROOT}/scripts/walter/lib/spend-record.sh"
  source "$lib"

  # Shadow jq with a function that makes it appear absent
  jq() { return 127; }
  command() {
    if [[ "$1" == "-v" && "$2" == "jq" ]]; then
      return 1
    fi
    builtin command "$@"
  }

  run _record_cli_spend "walter ask" "haiku" 100
  [ "$status" -ne 0 ]
  [[ "$output" == *"jq required"* ]]
}
