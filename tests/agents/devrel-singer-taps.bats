#!/usr/bin/env bats
# Phase V — Part B: Singer taps wrapper validation
# Covers: AC-6 (Google Ads), AC-7 (Meta), AC-9 (TikTok stub)
#
# These are code-level tests of the Singer JSON → analytics_events mapping
# functions. The actual API calls are paperwork-gated (operator prereqs V-prereq-1
# through V-prereq-3). Tests run against mock Singer output fixtures.
#
# Refs: docs/specs/devrel-analytics-stack.md

setup() {
  SINGER_DIR="$BATS_TEST_DIRNAME/../../setup/walter-host/singer"
}

# ── Directory structure ───────────────────────────────────────────────────────

@test "singer taps directory exists" {
  [[ -d "$SINGER_DIR" ]]
}

@test "singer taps runner script exists" {
  [[ -f "$SINGER_DIR/run-tap.sh" ]]
}

@test "run-tap.sh is executable" {
  [[ -f "$SINGER_DIR/run-tap.sh" ]] && [[ -x "$SINGER_DIR/run-tap.sh" ]]
}

@test "singer mapper Python script exists" {
  [[ -f "$SINGER_DIR/singer_to_analytics.py" ]]
}

@test "singer n8n workflow for google-ads exists" {
  [[ -f "$BATS_TEST_DIRNAME/../../setup/walter-host/services/n8n/workflows/google-ads-pull.json" ]]
}

@test "google-ads workflow references tap-google-ads" {
  local f="$BATS_TEST_DIRNAME/../../setup/walter-host/services/n8n/workflows/google-ads-pull.json"
  [[ -f "$f" ]]
  grep -qi "tap-google-ads\|google.ads\|google_ads" "$f"
}

@test "singer n8n workflow for meta exists" {
  [[ -f "$BATS_TEST_DIRNAME/../../setup/walter-host/services/n8n/workflows/meta-ads-pull.json" ]]
}

@test "meta workflow references tap-facebook or meta" {
  local f="$BATS_TEST_DIRNAME/../../setup/walter-host/services/n8n/workflows/meta-ads-pull.json"
  [[ -f "$f" ]]
  grep -qi "tap-facebook\|meta\|facebook" "$f"
}

# ── Python mapper unit tests (via python -m pytest inline) ───────────────────

@test "singer_to_analytics.py imports cleanly (no syntax errors)" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  python3 -c "
import ast, sys
with open('$SINGER_DIR/singer_to_analytics.py') as f:
    src = f.read()
try:
    ast.parse(src)
    sys.exit(0)
except SyntaxError as e:
    print(e)
    sys.exit(1)
"
}

@test "singer_to_analytics.py maps RECORD type to analytics_events row" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  local singer_dir="$SINGER_DIR"
  python3 - "$singer_dir" <<'PYTHON'
import sys
sys.path.insert(0, sys.argv[1])

import json
singer_record = {
    "type": "RECORD",
    "stream": "google_ads_campaigns",
    "record": {
        "date": "2026-05-01",
        "campaign_id": "123456",
        "ad_group_id": "789",
        "ad_id": "999",
        "impressions": 1000,
        "clicks": 50,
        "cost_micros": 5000000,
        "conversions": 3
    }
}

from singer_to_analytics import map_singer_record

rows = map_singer_record(singer_record, source_tap="google_ads")
assert len(rows) >= 1, f"Expected at least 1 row, got {len(rows)}"

row = rows[0]
assert "platform" in row, "Missing platform field"
assert "campaign_id" in row or "content_id" in row, "Missing campaign/content id"
assert row.get("platform") in ("google", "google_ads", "youtube"), f"Wrong platform: {row.get('platform')}"
print("OK")
PYTHON
}

@test "singer_to_analytics.py handles missing optional fields gracefully" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  local singer_dir="$SINGER_DIR"
  python3 - "$singer_dir" <<'PYTHON'
import sys
sys.path.insert(0, sys.argv[1])

from singer_to_analytics import map_singer_record

minimal = {
    "type": "RECORD",
    "stream": "google_ads_campaigns",
    "record": {
        "date": "2026-05-01",
        "campaign_id": "abc",
        "cost_micros": 0
    }
}

rows = map_singer_record(minimal, source_tap="google_ads")
print(f"OK — got {len(rows)} rows for minimal record")
PYTHON
}

@test "singer prereqs check script exists" {
  [[ -f "$SINGER_DIR/check-prereqs.sh" ]]
}

@test "singer check-prereqs.sh is executable" {
  [[ -f "$SINGER_DIR/check-prereqs.sh" ]] && [[ -x "$SINGER_DIR/check-prereqs.sh" ]]
}

@test "singer check-prereqs prints PENDING for unapproved tap" {
  command -v bash >/dev/null 2>&1 || skip "bash required"
  local script="$SINGER_DIR/check-prereqs.sh"
  [[ -f "$script" ]] || skip "check-prereqs.sh not found"

  # When Google Ads token is not set, should report PENDING not error
  output=$(GOOGLE_ADS_DEVELOPER_TOKEN="" bash "$script" 2>&1 || true)
  echo "Script output: $output"
  # Must not exit with code that would block deployment — just print status
  [[ "$output" =~ PENDING|pending|not.*set|missing|required ]]
}
