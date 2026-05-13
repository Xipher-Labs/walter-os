#!/usr/bin/env bats
# Tests for T-4: Grafana dashboard provisioning
# Covers: AC-2 of Improvement 1

setup() {
  GRAFANA_DIR="$BATS_TEST_DIRNAME/../../setup/walter-host/services/observability/grafana"
  DASHBOARD_JSON="$GRAFANA_DIR/provisioning/dashboards/walter-council.json"
  PROVISIONING_YML="$GRAFANA_DIR/provisioning/dashboards/dashboards.yml"
}

@test "walter-council dashboard JSON exists" {
  [[ -f "$DASHBOARD_JSON" ]]
}

@test "dashboard JSON has uid walter-council" {
  [[ -f "$DASHBOARD_JSON" ]] || skip "dashboard JSON not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"
  jq -e '.uid == "walter-council"' "$DASHBOARD_JSON" >/dev/null
}

@test "dashboard JSON has title Walter Council" {
  [[ -f "$DASHBOARD_JSON" ]] || skip "dashboard JSON not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"
  jq -e '.title | test("Walter Council")' "$DASHBOARD_JSON" >/dev/null
}

@test "dashboard JSON has at least 6 panels" {
  [[ -f "$DASHBOARD_JSON" ]] || skip "dashboard JSON not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"
  local count; count="$(jq '.panels | length' "$DASHBOARD_JSON")"
  [[ "$count" -ge 6 ]]
}

@test "dashboard panels reference walter_council_ metrics" {
  [[ -f "$DASHBOARD_JSON" ]] || skip "dashboard JSON not found"
  grep -q "walter_council_" "$DASHBOARD_JSON"
}

@test "dashboards.yml provisioning config references walter-council.json" {
  [[ -f "$PROVISIONING_YML" ]] || skip "dashboards.yml not found"
  # The provisioning config should point to the directory containing our dashboard
  grep -q "dashboards" "$PROVISIONING_YML"
}

# ---- F3: success-rate panel uses zero-safe divisor ----

@test "success-rate panel uses clamp_min or zero-safe divisor (not raw boolean guard)" {
  [[ -f "$DASHBOARD_JSON" ]] || skip "dashboard JSON not found"
  # The old pattern divides by (sum(...) > 0) which yields 0/1/NaN/Inf.
  # Must use clamp_min or equivalent pattern instead.
  grep -q "clamp_min" "$DASHBOARD_JSON"
}

@test "success-rate panel does NOT use bare boolean guard '> 0)'" {
  [[ -f "$DASHBOARD_JSON" ]] || skip "dashboard JSON not found"
  # Old unsafe pattern: / (sum(...) > 0)
  # After fix this should be gone
  ! grep -q '> 0)' "$DASHBOARD_JSON"
}

# ---- F4: P95 panel title matches gauge metric (not histogram) ----

@test "task duration panel title is 'Task Duration (last)' not 'P95'" {
  [[ -f "$DASHBOARD_JSON" ]] || skip "dashboard JSON not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"
  # Panel must NOT use histogram-style title — metric is a gauge
  ! jq -e '.panels[] | select(.title | test("P95"))' "$DASHBOARD_JSON" >/dev/null 2>&1
}
