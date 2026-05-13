#!/usr/bin/env bats
# Tests for T-25: setup/templates/trust-tiers.yml + install.sh integration
# Covers: AC-1 of Improvement 7

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  TEMPLATE="$REPO_ROOT/setup/templates/trust-tiers.yml"
}

@test "trust-tiers.yml template exists in repo" {
  [[ -f "$TEMPLATE" ]]
}

@test "install.sh references trust-tiers.yml template" {
  grep -q "trust-tiers" "$REPO_ROOT/install.sh"
}

@test "trust-tiers.yml has all 6 agents" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  local agents
  agents=$(yq '.agents | keys | .[]' "$TEMPLATE" 2>/dev/null)
  echo "$agents" | grep -qx "triage"
  echo "$agents" | grep -qx "researcher"
  echo "$agents" | grep -qx "coder"
  echo "$agents" | grep -qx "reviewer"
  echo "$agents" | grep -qx "janitor"
  echo "$agents" | grep -qx "liaison"
}

@test "reviewer has tier high" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  local tier
  tier=$(yq '.agents.reviewer.tier' "$TEMPLATE" 2>/dev/null)
  [[ "$tier" == "high" ]]
}

@test "janitor has tier low" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  local tier
  tier=$(yq '.agents.janitor.tier' "$TEMPLATE" 2>/dev/null)
  [[ "$tier" == "low" ]]
}

@test "liaison has tier low" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  local tier
  tier=$(yq '.agents.liaison.tier' "$TEMPLATE" 2>/dev/null)
  [[ "$tier" == "low" ]]
}

@test "triage, researcher, coder have tier medium" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  for agent in triage researcher coder; do
    local tier
    tier=$(yq ".agents.${agent}.tier" "$TEMPLATE" 2>/dev/null)
    [[ "$tier" == "medium" ]] || { echo "Expected medium for $agent, got $tier"; return 1; }
  done
}

@test "janitor overrides include write-wiki-pages allow" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  local val
  val=$(yq '.agents.janitor.overrides["write-wiki-pages"]' "$TEMPLATE" 2>/dev/null)
  [[ "$val" == "allow" ]]
}

@test "liaison overrides include write-wiki-pages allow" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  local val
  val=$(yq '.agents.liaison.overrides["write-wiki-pages"]' "$TEMPLATE" 2>/dev/null)
  [[ "$val" == "allow" ]]
}
