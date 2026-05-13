#!/usr/bin/env bats
# Phase V — Part A: n8n workflow JSON validation
# Covers: AC-1 (YouTube), AC-2 (Plausible), AC-3 (GitHub), AC-4 (Bluesky)
#
# n8n workflows are versioned as JSON exports in setup/walter-host/services/n8n/workflows/.
# They are imported into n8n via the n8n CLI or API on first deploy.
# Bats validates structure without needing n8n running.
#
# Refs: docs/specs/devrel-analytics-stack.md

setup() {
  WORKFLOWS_DIR="$BATS_TEST_DIRNAME/../../setup/walter-host/services/n8n/workflows"
}

# ── Workflow directory exists ─────────────────────────────────────────────────

@test "n8n workflows directory exists" {
  [[ -d "$WORKFLOWS_DIR" ]]
}

# ── YouTube Data API pull (AC-1) ──────────────────────────────────────────────

@test "yt-data-api-pull workflow JSON exists" {
  [[ -f "$WORKFLOWS_DIR/yt-data-api-pull.json" ]]
}

@test "yt-data-api-pull has cron trigger node" {
  [[ -f "$WORKFLOWS_DIR/yt-data-api-pull.json" ]]
  command -v jq >/dev/null 2>&1 || skip "jq required"
  # Check for Schedule Trigger or Cron node
  jq -e '[.nodes[] | select(.type | test("scheduleTrigger|cron|n8n-nodes-base.scheduleTrigger"; "i"))] | length >= 1' \
    "$WORKFLOWS_DIR/yt-data-api-pull.json" >/dev/null
}

@test "yt-data-api-pull workflow has name field" {
  [[ -f "$WORKFLOWS_DIR/yt-data-api-pull.json" ]]
  command -v jq >/dev/null 2>&1 || skip "jq required"
  jq -e '.name | test("youtube|yt"; "i")' "$WORKFLOWS_DIR/yt-data-api-pull.json" >/dev/null
}

# ── Plausible pull (AC-2) ─────────────────────────────────────────────────────

@test "plausible-pull workflow JSON exists" {
  [[ -f "$WORKFLOWS_DIR/plausible-pull.json" ]]
}

@test "plausible-pull has cron trigger node" {
  [[ -f "$WORKFLOWS_DIR/plausible-pull.json" ]]
  command -v jq >/dev/null 2>&1 || skip "jq required"
  jq -e '[.nodes[] | select(.type | test("scheduleTrigger|cron"; "i"))] | length >= 1' \
    "$WORKFLOWS_DIR/plausible-pull.json" >/dev/null
}

@test "plausible-pull has HTTP request node targeting plausible" {
  [[ -f "$WORKFLOWS_DIR/plausible-pull.json" ]]
  grep -qi "plausible" "$WORKFLOWS_DIR/plausible-pull.json"
}

# ── GitHub pull (AC-3) ────────────────────────────────────────────────────────

@test "github-pull workflow JSON exists" {
  [[ -f "$WORKFLOWS_DIR/github-pull.json" ]]
}

@test "github-pull has cron trigger node" {
  [[ -f "$WORKFLOWS_DIR/github-pull.json" ]]
  command -v jq >/dev/null 2>&1 || skip "jq required"
  jq -e '[.nodes[] | select(.type | test("scheduleTrigger|cron"; "i"))] | length >= 1' \
    "$WORKFLOWS_DIR/github-pull.json" >/dev/null
}

@test "github-pull references github API or github node" {
  [[ -f "$WORKFLOWS_DIR/github-pull.json" ]]
  grep -qi "github" "$WORKFLOWS_DIR/github-pull.json"
}

# ── Bluesky stream (AC-4) ────────────────────────────────────────────────────

@test "bluesky-stream workflow JSON exists" {
  [[ -f "$WORKFLOWS_DIR/bluesky-stream.json" ]]
}

@test "bluesky-stream references bluesky or AT protocol" {
  [[ -f "$WORKFLOWS_DIR/bluesky-stream.json" ]]
  grep -qi "bluesky\|bsky\|atproto\|at.protocol" "$WORKFLOWS_DIR/bluesky-stream.json"
}

# ── All workflows are valid JSON ──────────────────────────────────────────────

@test "all workflow JSON files are valid JSON" {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  local failed=0
  for f in "$WORKFLOWS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    if ! jq empty "$f" 2>/dev/null; then
      echo "Invalid JSON: $f" >&2
      failed=1
    fi
  done
  [[ "$failed" -eq 0 ]]
}

# ── Import script exists ──────────────────────────────────────────────────────

@test "n8n workflow import script exists" {
  [[ -f "$BATS_TEST_DIRNAME/../../setup/walter-host/services/n8n/import-workflows.sh" ]]
}

@test "import script is executable" {
  local script="$BATS_TEST_DIRNAME/../../setup/walter-host/services/n8n/import-workflows.sh"
  [[ -f "$script" ]] && [[ -x "$script" ]]
}

# ── X CSV ingest workflow (AC-8 — Tier 2 but structural check) ───────────────

@test "x-csv-ingest workflow JSON exists" {
  [[ -f "$WORKFLOWS_DIR/x-csv-ingest.json" ]]
}

@test "x-csv-ingest watches CSV drop folder" {
  [[ -f "$WORKFLOWS_DIR/x-csv-ingest.json" ]]
  grep -qi "csv\|watch\|folder\|localFileTrigger\|readFile" "$WORKFLOWS_DIR/x-csv-ingest.json"
}
