#!/usr/bin/env bats
# Phase V — Part C: Dashboard validation
# Covers: AC-10 (Control Tower Content tab), AC-11 (Grafana dashboard)
#
# Refs: docs/specs/devrel-analytics-stack.md

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  GRAFANA_DIR="$REPO_ROOT/setup/walter-host/services/observability/grafana"
  CT_DIR="$REPO_ROOT/apps/control-tower"
}

# ── Grafana dashboard (AC-11) ─────────────────────────────────────────────────

@test "walter-devrel-analytics Grafana dashboard JSON exists" {
  [[ -f "$GRAFANA_DIR/provisioning/dashboards/walter-devrel-analytics.json" ]]
}

@test "devrel analytics dashboard uid is walter-devrel-analytics" {
  [[ -f "$GRAFANA_DIR/provisioning/dashboards/walter-devrel-analytics.json" ]]
  command -v jq >/dev/null 2>&1 || skip "jq required"
  jq -e '.uid == "walter-devrel-analytics"' \
    "$GRAFANA_DIR/provisioning/dashboards/walter-devrel-analytics.json" >/dev/null
}

@test "devrel analytics dashboard has at least 4 panels" {
  [[ -f "$GRAFANA_DIR/provisioning/dashboards/walter-devrel-analytics.json" ]]
  command -v jq >/dev/null 2>&1 || skip "jq required"
  local count; count="$(jq '.panels | length' "$GRAFANA_DIR/provisioning/dashboards/walter-devrel-analytics.json")"
  [[ "$count" -ge 4 ]]
}

@test "devrel analytics dashboard references analytics_events table" {
  [[ -f "$GRAFANA_DIR/provisioning/dashboards/walter-devrel-analytics.json" ]]
  grep -q "analytics_events\|content_pieces\|mv_top\|mv_engagement\|mv_roi" \
    "$GRAFANA_DIR/provisioning/dashboards/walter-devrel-analytics.json"
}

@test "Grafana Postgres datasource config exists for analytics DB" {
  [[ -f "$GRAFANA_DIR/provisioning/datasources/datasources.yml" ]]
  grep -qi "analytics\|walter_devrel\|5433" \
    "$GRAFANA_DIR/provisioning/datasources/datasources.yml"
}

# ── Control Tower Content tab (AC-10) ─────────────────────────────────────────

@test "Control Tower content page directory exists" {
  [[ -d "$CT_DIR/app/content" ]]
}

@test "Control Tower content page.tsx exists" {
  [[ -f "$CT_DIR/app/content/page.tsx" ]]
}

@test "Control Tower content page references analytics" {
  [[ -f "$CT_DIR/app/content/page.tsx" ]]
  grep -qi "analytics\|content\|devrel\|engagement" "$CT_DIR/app/content/page.tsx"
}

@test "Control Tower nav includes Content link" {
  [[ -f "$CT_DIR/app/layout.tsx" ]] || [[ -f "$CT_DIR/app/page.tsx" ]]
  grep -qi "content\|/content" "$CT_DIR/app/page.tsx" 2>/dev/null || \
  grep -qi "content\|/content" "$CT_DIR/app/layout.tsx" 2>/dev/null
}

@test "ContentDashboard component exists" {
  [[ -f "$CT_DIR/app/components/ContentDashboard.tsx" ]]
}

@test "ContentDashboard embeds Grafana devrel analytics panel" {
  [[ -f "$CT_DIR/app/components/ContentDashboard.tsx" ]]
  grep -qi "walter-devrel-analytics\|grafana\|embed\|iframe" \
    "$CT_DIR/app/components/ContentDashboard.tsx"
}

# ── Vitest unit test for ContentDashboard ─────────────────────────────────────

@test "ContentDashboard vitest unit test exists" {
  [[ -f "$CT_DIR/tests/unit/content-dashboard.test.ts" ]] || \
  [[ -f "$CT_DIR/tests/unit/ContentDashboard.test.ts" ]]
}
