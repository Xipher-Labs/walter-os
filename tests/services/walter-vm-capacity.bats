#!/usr/bin/env bats
# Static assertions for Walter-VM capacity alert thresholds.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WATCHDOG="$REPO_ROOT/setup/walter-host/services/alerting/walter-vm-watchdog.sh"
  GRAFANA_RULES="$REPO_ROOT/setup/walter-host/services/observability/grafana/provisioning/alerting/rules.yml"
  CAPACITY_ADR="$REPO_ROOT/docs/decisions/0027-ai-stack-capacity.md"
}

@test "walter-vm watchdog load threshold matches confirmed 16 vCPU host" {
  [[ -f "$WATCHDOG" ]]

  grep -q "16 vCPU" "$WATCHDOG"
  grep -q "l > 16.0" "$WATCHDOG"
  grep -q ">16.0, 16 vCPU pinned" "$WATCHDOG"

  ! grep -q "8 vCPU" "$WATCHDOG"
  ! grep -q "l > 8.0" "$WATCHDOG"
  ! grep -q ">8.0, 8 vCPU pinned" "$WATCHDOG"
}

@test "Grafana load alert matches confirmed 16 vCPU host" {
  [[ -f "$GRAFANA_RULES" ]]

  grep -q "Load 1m > vCPU count (16)" "$GRAFANA_RULES"
  grep -q "title: Load avg 1m > 16" "$GRAFANA_RULES"
  grep -q "params: \\[16\\]" "$GRAFANA_RULES"
  grep -q "summary: Walter-VM load1m > 16 (= vCPU count)" "$GRAFANA_RULES"
}

@test "capacity decision records no CPU resize requirement" {
  [[ -f "$CAPACITY_ADR" ]]

  grep -q "16 vCPU" "$CAPACITY_ADR"
  grep -q "30 GiB" "$CAPACITY_ADR"
  grep -q "No immediate CPU resize" "$CAPACITY_ADR"
  grep -q "load ~5" "$CAPACITY_ADR"
}
