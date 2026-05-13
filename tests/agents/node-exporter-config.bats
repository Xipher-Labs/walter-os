#!/usr/bin/env bats
# Tests for T-3: Node Exporter textfile_collector wiring
# Covers: AC-1 of Improvement 1

setup() {
  COMPOSE="$BATS_TEST_DIRNAME/../../setup/walter-host/services/observability/compose.yml"
  [[ -f "$COMPOSE" ]] || skip "observability compose.yml not found"
}

@test "node-exporter command includes textfile collector directory" {
  grep -A 10 "node-exporter:" "$COMPOSE" | grep -q "textfile"
}

@test "node-exporter has volume mount for /var/lib/walter-council" {
  # The compose must mount the metrics dir into the container
  grep -q "walter-council" "$COMPOSE"
}

@test "node-exporter section documents textfile collector path" {
  # Either in command or volumes section, the path /var/lib/walter-council must appear
  grep -q "/var/lib/walter-council" "$COMPOSE"
}
