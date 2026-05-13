#!/usr/bin/env bats
# Tests for T-30: gate.lock enforcement EXPANDED in approval-gate.sh
# Confirms panic lock runs BEFORE trust tier checks and standing approvals.
# Covers: AC-3 of Improvement 8

setup() {
  HOOK="$BATS_TEST_DIRNAME/../../hooks/approval-gate.sh"
  [[ -x "$HOOK" ]] || skip "approval-gate.sh not executable"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  export WALTER_CONFIG="$(mktemp -d -t walter-gatelock-XXXXXX)"
  export WALTER_AGENT_PLANE_ISSUE=
  unset PLANE_API_TOKEN PLANE_API_URL PLANE_WORKSPACE PLANE_PROJECT
}

teardown() {
  rm -rf "$WALTER_CONFIG"
}

@test "gate.lock blocks before trust tier logic (trust cannot override panic)" {
  command -v yq >/dev/null 2>&1 || skip "yq required for trust tier test"
  # Give reviewer high tier
  cat > "$WALTER_CONFIG/trust-tiers.yml" <<'TIERS'
agents:
  reviewer:
    tier: high
    overrides: {}
TIERS
  # Also set gate.lock
  printf '%s\npanic test\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WALTER_CONFIG/gate.lock"
  export WALTER_AGENT_NAME=reviewer

  # Even with high tier + trust-tiers.yml, gate.lock blocks
  run "$HOOK" check "git push origin feature/my-branch"
  [[ "$status" -eq 7 ]]
  [[ "$output" =~ "panic lock" || "$output" =~ "lock" ]]
}

@test "gate.lock message references unlock command" {
  printf '%s\npanic test\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WALTER_CONFIG/gate.lock"
  run "$HOOK" check "ls /tmp"
  [[ "$status" -eq 7 ]]
  # Message should tell operator how to unlock
  [[ "$output" =~ "unlock" ]]
}

@test "gate.lock blocks hook mode (JSON input) with block decision" {
  printf '%s\npanic\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WALTER_CONFIG/gate.lock"
  input='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
  result=$(echo "$input" | "$HOOK")
  [[ "$(echo "$result" | jq -r '.decision')" == "block" ]]
}

@test "gate.lock block reason is included in JSON hook mode output" {
  printf '%s\npanic\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WALTER_CONFIG/gate.lock"
  input='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
  result=$(echo "$input" | "$HOOK")
  [[ "$(echo "$result" | jq -r '.reason')" =~ "lock" || "$(echo "$result" | jq -r '.reason')" =~ "panic" ]]
}
