#!/usr/bin/env bats
# Tests for T-26: Trust tier enforcement in approval-gate.sh
# Covers: AC-2, AC-3 of Improvement 7

setup() {
  HOOK="$BATS_TEST_DIRNAME/../../hooks/approval-gate.sh"
  [[ -x "$HOOK" ]] || skip "approval-gate.sh not executable"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  export WALTER_CONFIG="$(mktemp -d -t walter-trust-test-XXXXXX)"
  export WALTER_AGENT_PLANE_ISSUE=
  unset PLANE_API_TOKEN PLANE_API_URL PLANE_WORKSPACE PLANE_PROJECT

  # Write a trust-tiers.yml with reviewer=high, janitor=low
  cat > "$WALTER_CONFIG/trust-tiers.yml" <<'TIERS'
agents:
  reviewer:
    tier: high
    overrides: {}
  janitor:
    tier: low
    overrides: {}
  triage:
    tier: medium
    overrides: {}
  researcher:
    tier: medium
    overrides: {}
  coder:
    tier: medium
    overrides: {}
  liaison:
    tier: low
    overrides: {}
TIERS
}

teardown() {
  rm -rf "$WALTER_CONFIG"
}

# --- tier high: git push feature/* is auto-allowed ---

@test "reviewer (high tier) can push to feature branch" {
  command -v yq >/dev/null 2>&1 || skip "yq required for tier lookup"
  export WALTER_AGENT_NAME=reviewer
  run "$HOOK" check "git push origin feature/test-branch"
  [[ "$status" -eq 0 ]]
}

@test "reviewer (high tier) can create PR" {
  command -v yq >/dev/null 2>&1 || skip "yq required for tier lookup"
  export WALTER_AGENT_NAME=reviewer
  run "$HOOK" check "gh pr create --title 'test'" --tool Bash
  [[ "$status" -eq 0 ]]
}

# --- tier low: git push feature/* is blocked ---

@test "janitor (low tier) cannot push to feature branch" {
  command -v yq >/dev/null 2>&1 || skip "yq required for tier lookup"
  export WALTER_AGENT_NAME=janitor
  run "$HOOK" check "git push origin feature/test-branch"
  [[ "$status" -eq 7 ]]
}

# --- panic lock overrides trust tier ---

@test "panic lock blocks reviewer despite high tier" {
  command -v yq >/dev/null 2>&1 || skip "yq required for tier lookup"
  touch "$WALTER_CONFIG/gate.lock"
  export WALTER_AGENT_NAME=reviewer
  run "$HOOK" check "git push origin feature/test-branch"
  [[ "$status" -eq 7 ]]
  [[ "$output" =~ "panic lock" || "$output" =~ "lock" ]]
}

# --- trust tier does not unlock hardcoded-always-block categories ---

@test "reviewer (high tier) cannot push to main" {
  export WALTER_AGENT_NAME=reviewer
  run "$HOOK" check "git push origin main"
  [[ "$status" -eq 7 ]]
}

@test "reviewer (high tier) cannot rm -rf" {
  export WALTER_AGENT_NAME=reviewer
  run "$HOOK" check "rm -rf /var/lib/data"
  [[ "$status" -eq 7 ]]
}

# --- fallback: missing trust-tiers.yml does not break gate ---

@test "gate allows read ops even when trust-tiers.yml missing" {
  rm -f "$WALTER_CONFIG/trust-tiers.yml"
  export WALTER_AGENT_NAME=unknown-agent
  run "$HOOK" check "ls /tmp" --tool Bash
  [[ "$status" -eq 0 ]]
}

@test "gate blocks protected tiered ops when trust-tiers.yml missing" {
  rm -f "$WALTER_CONFIG/trust-tiers.yml"
  export WALTER_AGENT_NAME=reviewer
  run "$HOOK" check "git push origin feature/test-branch"
  [[ "$status" -eq 7 ]]
  [[ "$output" =~ "trust tier" ]]
}
