#!/usr/bin/env bats
# Static assertions for Walter-VM capacity alert thresholds.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WATCHDOG="$REPO_ROOT/setup/walter-host/services/alerting/walter-vm-watchdog.sh"
  GRAFANA_RULES="$REPO_ROOT/setup/walter-host/services/observability/grafana/provisioning/alerting/rules.yml"
  CAPACITY_ADR="$REPO_ROOT/docs/decisions/0027-ai-stack-capacity.md"
}

@test "walter-vm watchdog derives load threshold from runtime CPU count" {
  [[ -f "$WATCHDOG" ]]

  grep -Fq 'CPU_CORES=$(nproc' "$WATCHDOG"
  grep -Fq 'LOAD_HIGH=$(awk -v l="$LOAD_1M" -v c="$CPU_CORES"' "$WATCHDOG"
  grep -Fq 'l > c' "$WATCHDOG"
  grep -Fq '>runtime vCPU count ${CPU_CORES}' "$WATCHDOG"

  ! grep -Fq "16 vCPU pinned" "$WATCHDOG"
  ! grep -Fq "l > 16.0" "$WATCHDOG"
  ! grep -Fq "8 vCPU" "$WATCHDOG"
  ! grep -Fq "l > 8.0" "$WATCHDOG"
}

@test "Grafana load alert derives threshold from runtime CPU metrics" {
  [[ -f "$GRAFANA_RULES" ]]

  grep -Fq "Load 1m > runtime vCPU count" "$GRAFANA_RULES"
  grep -Fq "title: Load avg 1m > vCPU count" "$GRAFANA_RULES"
  grep -Fq 'node_load1 > on(instance, job) count by (instance, job) (node_cpu_seconds_total{mode="idle"})' "$GRAFANA_RULES"
  grep -Fq "params: [0]" "$GRAFANA_RULES"
  grep -Fq "summary: Walter-VM load1m > runtime vCPU count" "$GRAFANA_RULES"

  ! grep -Fq "params: [16]" "$GRAFANA_RULES"
  ! grep -Fq "Load avg 1m > 16" "$GRAFANA_RULES"
}

@test "capacity decision records no CPU resize requirement" {
  [[ -f "$CAPACITY_ADR" ]]

  grep -Fq "16 vCPU / 30 GiB" "$CAPACITY_ADR"
  grep -Fq "runtime CPU count" "$CAPACITY_ADR"
  grep -Fq "No immediate CPU resize" "$CAPACITY_ADR"
  grep -Fq "load ~5" "$CAPACITY_ADR"
}
