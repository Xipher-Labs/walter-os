#!/usr/bin/env bats
# tests/oss/security-no-weak-defaults.bats
# Verify that no weak hardcoded credentials appear in service configs.
# Each test corresponds to a specific audit finding.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

# ── A-1: ccr-internal ────────────────────────────────────────────────────────

@test "A-1: ccr-internal does not appear in litellm/config.yaml" {
  run grep -n 'ccr-internal' "$REPO_ROOT/setup/walter-host/services/litellm/config.yaml"
  [ "$status" -ne 0 ]
}

@test "A-1: ccr-internal does not appear in llm-proxies/compose.yml" {
  run grep -n 'ccr-internal' "$REPO_ROOT/setup/walter-host/services/llm-proxies/compose.yml"
  [ "$status" -ne 0 ]
}

@test "A-1: ccr-internal does not appear anywhere in setup/ tree" {
  run grep -rn 'ccr-internal' "$REPO_ROOT/setup/"
  [ "$status" -ne 0 ]
}

@test "A-1: CCR_APIKEY uses :? form in llm-proxies compose (fail-loud)" {
  # The CCR_APIKEY env assignment must use :? (fail-loud), not :- (soft-default)
  run grep -E 'CCR_APIKEY:[[:space:]]*\$\{CCR_APIKEY:-' \
    "$REPO_ROOT/setup/walter-host/services/llm-proxies/compose.yml"
  [ "$status" -ne 0 ]
}

# ── A-2: penpot + synapse weak defaults ───────────────────────────────────────

@test "A-2: penpotpass does not appear in root compose.yml" {
  run grep -n 'penpotpass' "$REPO_ROOT/compose.yml"
  [ "$status" -ne 0 ]
}

@test "A-2: PENPOT_SECRET_KEY changeme does not appear in root compose.yml" {
  run grep -n 'changeme-generate-with-openssl-rand' "$REPO_ROOT/compose.yml"
  [ "$status" -ne 0 ]
}

@test "A-2: SYNAPSE_DB_PASS changeme does not appear in root compose.yml" {
  run grep -n 'changeme-set-before-using-comms-profile' "$REPO_ROOT/compose.yml"
  [ "$status" -ne 0 ]
}

# ── A-3: openclaw gateway token ───────────────────────────────────────────────

@test "A-3: OPENCLAW_GATEWAY_TOKEN changeme does not appear in root compose.yml" {
  run grep -n 'changeme-set-before-using-assistant-profile' "$REPO_ROOT/compose.yml"
  [ "$status" -ne 0 ]
}

@test "A-3: OPENCLAW_GATEWAY_TOKEN parameterized + runtime-guarded in root compose" {
  # Codex R2 P1.1: root compose can NOT use :?required for OPENCLAW_GATEWAY_TOKEN
  #   (would block core profile for adopters not using assistant). Per-service
  #   compose at setup/walter-host/services/openclaw/compose.yml keeps :?required.
  # Codex R3 P1.R3-2: empty token must fail-closed at RUNTIME inside the
  #   container command (not at compose-parse time). Guard added: 'set -e'
  #   block with 'if [ -z "${OPENCLAW_GATEWAY_TOKEN}" ]; then exit 1'.
  # This test verifies both invariants:
  run grep 'OPENCLAW_GATEWAY_TOKEN' "$REPO_ROOT/compose.yml"
  [ "$status" -eq 0 ]
  # 1. Env var is referenced (parameterized, not hardcoded)
  echo "$output" | grep -qE '\$\{OPENCLAW_GATEWAY_TOKEN'
  # 2. No weak hardcoded defaults
  ! echo "$output" | grep -qE '(changeme|placeholder|default-token|set-before-using)'
  # 3. Runtime guard exists (empty-string check that exits 1)
  grep -qE 'OPENCLAW_GATEWAY_TOKEN\}".*\]; then|-z.*OPENCLAW_GATEWAY_TOKEN' "$REPO_ROOT/compose.yml"
}

# ── A-5: claude-code-router @latest ──────────────────────────────────────────

@test "A-5: @latest not used in llm-proxies compose.yml" {
  run grep '@latest' "$REPO_ROOT/setup/walter-host/services/llm-proxies/compose.yml"
  [ "$status" -ne 0 ]
}
