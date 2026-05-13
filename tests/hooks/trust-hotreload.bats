#!/usr/bin/env bats
# Tests for T-28: Hot-reload of trust tiers in approval-gate.sh
# Covers: AC-5 of Improvement 7
#
# approval-gate.sh is a short-lived process invoked per hook event.
# It reads trust-tiers.yml fresh on every invocation. This test
# verifies that modifying trust-tiers.yml between invocations takes
# effect immediately (no daemon restart required).

setup() {
  HOOK="$BATS_TEST_DIRNAME/../../hooks/approval-gate.sh"
  [[ -x "$HOOK" ]] || skip "approval-gate.sh not executable"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  export WALTER_CONFIG="$(mktemp -d -t walter-hotreload-XXXXXX)"
  export WALTER_AGENT_PLANE_ISSUE=
  unset PLANE_API_TOKEN PLANE_API_URL PLANE_WORKSPACE PLANE_PROJECT
}

teardown() {
  rm -rf "$WALTER_CONFIG"
}

@test "hot-reload: block before tier change, allow after" {
  command -v yq >/dev/null 2>&1 || skip "yq required for tier lookup"

  # Start: janitor (low tier) — push to feature blocked
  cat > "$WALTER_CONFIG/trust-tiers.yml" <<'TIERS'
agents:
  janitor:
    tier: low
    overrides: {}
TIERS

  export WALTER_AGENT_NAME=janitor
  run "$HOOK" check "git push origin feature/test-branch"
  [[ "$status" -eq 7 ]]

  # Upgrade janitor to medium tier (hot edit)
  yq -i '.agents.janitor.tier = "medium"' "$WALTER_CONFIG/trust-tiers.yml"

  # Same command — now allowed (no daemon restart)
  run "$HOOK" check "git push origin feature/test-branch"
  [[ "$status" -eq 0 ]]
}

@test "hot-reload: gate.lock file is re-read on each invocation" {
  # No lock initially
  export WALTER_AGENT_NAME=test-agent
  run "$HOOK" check "ls /tmp"
  [[ "$status" -eq 0 ]]

  # Create lock — next invocation should block
  printf '%s\npanic test\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WALTER_CONFIG/gate.lock"
  run "$HOOK" check "ls /tmp"
  [[ "$status" -eq 7 ]]

  # Remove lock — next invocation should allow again
  rm -f "$WALTER_CONFIG/gate.lock"
  run "$HOOK" check "ls /tmp"
  [[ "$status" -eq 0 ]]
}

@test "approval-gate.sh header documents hot-reload behavior" {
  HOOK_FILE="$BATS_TEST_DIRNAME/../../hooks/approval-gate.sh"
  grep -qi "hot.reload\|short.lived\|fresh\|re-read" "$HOOK_FILE"
}
