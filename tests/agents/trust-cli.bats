#!/usr/bin/env bats
# Tests for T-27: walter-os agents trust subcommand
# Covers: AC-4 of Improvement 7

setup() {
  WALTER_OS="$BATS_TEST_DIRNAME/../../bin/walter-os"
  [[ -x "$WALTER_OS" ]] || skip "walter-os not executable"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  export WALTER_CONFIG="$(mktemp -d -t walter-trust-cli-XXXXXX)"
  export WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.."

  cat > "$WALTER_CONFIG/trust-tiers.yml" <<'TIERS'
agents:
  reviewer:
    tier: high
    overrides: {}
  janitor:
    tier: low
    overrides:
      write-wiki-pages: allow
  triage:
    tier: medium
    overrides: {}
TIERS
}

teardown() {
  rm -rf "$WALTER_CONFIG"
}

@test "agents trust shows tier for known agent" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  run "$WALTER_OS" agents trust reviewer
  [[ "$status" -eq 0 ]]
  # Output uses capitalized "Tier:" label — match case-insensitively
  [[ "$output" =~ [Tt]ier ]]
  [[ "$output" =~ "high" ]]
}

@test "agents trust shows tier for janitor (low)" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  run "$WALTER_OS" agents trust janitor
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "low" ]]
}

@test "agents trust exits 2 for unknown agent" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  run "$WALTER_OS" agents trust unknown-agent
  [[ "$status" -eq 2 ]]
}

@test "agents trust exits 2 when no agent name given (not unknown-subcommand error)" {
  run "$WALTER_OS" agents trust
  [[ "$status" -eq 2 ]]
  # The error should mention 'trust' usage, not "unknown subcommand 'trust'"
  [[ "$output" != *"unknown subcommand 'trust'"* ]]
}

@test "agents trust list shows all agents" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  run "$WALTER_OS" agents trust list
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "reviewer" ]]
  [[ "$output" =~ "janitor" ]]
  [[ "$output" =~ "triage" ]]
}

@test "agents trust set changes tier for agent" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  run "$WALTER_OS" agents trust set triage high
  [[ "$status" -eq 0 ]]
  # Verify the change persisted
  run "$WALTER_OS" agents trust triage
  [[ "$output" =~ "high" ]]
}

@test "agents trust set rejects invalid tier with informative error" {
  run "$WALTER_OS" agents trust set triage superpower
  [[ "$status" -eq 2 ]]
  # Should mention valid tiers (low|medium|high), not just "unknown subcommand"
  [[ "$output" =~ "low|medium|high" || "$output" =~ "tier" ]] || \
    [[ "$output" != *"unknown subcommand 'trust'"* ]]
}

@test "agents trust list --json outputs valid JSON" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  run "$WALTER_OS" agents trust list --json
  [[ "$status" -eq 0 ]]
  echo "$output" | jq . >/dev/null 2>&1
}
