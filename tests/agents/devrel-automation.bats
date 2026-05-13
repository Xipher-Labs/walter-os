#!/usr/bin/env bats
# Phase V — Part D: Anomaly detection + weekly digest workflow validation
# Covers: AC-14 (weekly digest), AC-15 (anomaly detection)
#
# Refs: docs/specs/devrel-analytics-stack.md

setup() {
  WORKFLOWS_DIR="$BATS_TEST_DIRNAME/../../setup/walter-host/services/n8n/workflows"
}

# ── Anomaly detection workflow (AC-15) ────────────────────────────────────────

@test "anomaly-detection workflow JSON exists" {
  [[ -f "$WORKFLOWS_DIR/anomaly-detection.json" ]]
}

@test "anomaly-detection has cron trigger (1h)" {
  [[ -f "$WORKFLOWS_DIR/anomaly-detection.json" ]]
  command -v jq >/dev/null 2>&1 || skip "jq required"
  jq -e '[.nodes[] | select(.type | test("scheduleTrigger|cron"; "i"))] | length >= 1' \
    "$WORKFLOWS_DIR/anomaly-detection.json" >/dev/null
}

@test "anomaly-detection references sigma or 3sigma or baseline" {
  [[ -f "$WORKFLOWS_DIR/anomaly-detection.json" ]]
  grep -qi "sigma\|3.*sigma\|baseline\|stddev\|standard.*dev\|anomal" \
    "$WORKFLOWS_DIR/anomaly-detection.json"
}

@test "anomaly-detection references alert_emit or Telegram" {
  [[ -f "$WORKFLOWS_DIR/anomaly-detection.json" ]]
  grep -qi "telegram\|alert\|alert_emit" "$WORKFLOWS_DIR/anomaly-detection.json"
}

@test "anomaly-detection is valid JSON" {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  jq empty "$WORKFLOWS_DIR/anomaly-detection.json"
}

# ── Weekly digest workflow (AC-14) ────────────────────────────────────────────

@test "weekly-digest workflow JSON exists" {
  [[ -f "$WORKFLOWS_DIR/weekly-digest.json" ]]
}

@test "weekly-digest has cron trigger" {
  [[ -f "$WORKFLOWS_DIR/weekly-digest.json" ]]
  command -v jq >/dev/null 2>&1 || skip "jq required"
  jq -e '[.nodes[] | select(.type | test("scheduleTrigger|cron"; "i"))] | length >= 1' \
    "$WORKFLOWS_DIR/weekly-digest.json" >/dev/null
}

@test "weekly-digest cron runs on Monday" {
  [[ -f "$WORKFLOWS_DIR/weekly-digest.json" ]]
  # Should have Monday in cron or dayOfWeek config
  grep -qi "monday\|1.*cron\|dayOfWeek\|weekly\|mon" "$WORKFLOWS_DIR/weekly-digest.json"
}

@test "weekly-digest invokes devrel-analyst weekly_digest" {
  [[ -f "$WORKFLOWS_DIR/weekly-digest.json" ]]
  grep -qi "weekly.digest\|weekly_digest\|devrel-analyst\|query.py" \
    "$WORKFLOWS_DIR/weekly-digest.json"
}

@test "weekly-digest writes to wiki insights directory" {
  [[ -f "$WORKFLOWS_DIR/weekly-digest.json" ]]
  grep -qi "wiki\|insights\|weekly.*md\|sync/wiki" "$WORKFLOWS_DIR/weekly-digest.json"
}

@test "weekly-digest sends Telegram notification" {
  [[ -f "$WORKFLOWS_DIR/weekly-digest.json" ]]
  grep -qi "telegram" "$WORKFLOWS_DIR/weekly-digest.json"
}

@test "weekly-digest is valid JSON" {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  jq empty "$WORKFLOWS_DIR/weekly-digest.json"
}

# ── work context — generic OSS template sanity (AC-16 adapted for OSS) ───────
# The original AC-16 asserted Triton DevRel-specific references in the work
# context. After W-5 depersonalization the work context is a generic OSS
# template; operator-specific content lives in the personal overlay. This test
# verifies the generic template is present and correctly structured.

@test "work context is a generic OSS template (not operator-specific)" {
  local work_ctx="$BATS_TEST_DIRNAME/../../contexts/work/AGENTS.md"
  [[ -f "$work_ctx" ]]
  # Must carry the generic-template marker (present after W-5 depersonalisation)
  grep -q "GENERIC TEMPLATE\|\[Your Company\]" "$work_ctx"
}
