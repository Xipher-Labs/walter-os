#!/usr/bin/env bats
# Tests for n8n workflow JSON files — security and correctness
#
# Covers:
#   BLOCKER 2 — parameterized queries (no raw {{ $json }} in SQL strings)
#   WARN 2    — weekly-digest cron + ISO week formula
#   WARN 5    — anomaly detection min-sample HAVING guard
#   WARN 6    — weekly-digest heredoc injection
#
# Refs: docs/specs/devrel-analytics-stack.md

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WORKFLOWS_DIR="${REPO_ROOT}/setup/walter-host/services/n8n/workflows"

# ─────────────────────────────────────────────────────────────────────────────
# Helper: get the .query field from all "Upsert analytics_events" nodes
# ─────────────────────────────────────────────────────────────────────────────
get_upsert_queries() {
  local file="$1"
  python3 -c "
import json, sys
with open('$file') as f:
    wf = json.load(f)
queries = []
for node in wf.get('nodes', []):
    params = node.get('parameters', {})
    if 'query' in params and node.get('type','') == 'n8n-nodes-base.postgres':
        queries.append(params['query'])
for q in queries:
    print(q)
"
}

# ─────────────────────────────────────────────────────────────────────────────
# BLOCKER 2: Parameterized queries — no raw {{ $json }} in SQL .query field
# ─────────────────────────────────────────────────────────────────────────────

@test "yt-data-api-pull.json: no raw interpolation in SQL query" {
  queries=$(get_upsert_queries "$WORKFLOWS_DIR/yt-data-api-pull.json")
  echo "queries: $queries"
  # The query field itself must NOT contain {{ $json
  [[ "$queries" != *'{{ $json'* ]]
}

@test "plausible-pull.json: no raw interpolation in SQL query" {
  queries=$(get_upsert_queries "$WORKFLOWS_DIR/plausible-pull.json")
  echo "queries: $queries"
  [[ "$queries" != *'{{ $json'* ]]
}

@test "github-pull.json: no raw interpolation in SQL query" {
  queries=$(get_upsert_queries "$WORKFLOWS_DIR/github-pull.json")
  echo "queries: $queries"
  [[ "$queries" != *'{{ $json'* ]]
}

@test "bluesky-stream.json: no raw interpolation in SQL query" {
  queries=$(get_upsert_queries "$WORKFLOWS_DIR/bluesky-stream.json")
  echo "queries: $queries"
  [[ "$queries" != *'{{ $json'* ]]
}

@test "tiktok-pull.json: no raw interpolation in SQL query" {
  queries=$(get_upsert_queries "$WORKFLOWS_DIR/tiktok-pull.json")
  echo "queries: $queries"
  [[ "$queries" != *'{{ $json'* ]]
}

@test "x-csv-ingest.json: no raw interpolation in SQL query" {
  queries=$(get_upsert_queries "$WORKFLOWS_DIR/x-csv-ingest.json")
  echo "queries: $queries"
  [[ "$queries" != *'{{ $json'* ]]
}

@test "yt-data-api-pull.json: uses positional parameters (\$1, \$2 ...) in query" {
  queries=$(get_upsert_queries "$WORKFLOWS_DIR/yt-data-api-pull.json")
  echo "queries: $queries"
  [[ "$queries" == *'$1'* ]]
}

@test "plausible-pull.json: uses positional parameters in query" {
  queries=$(get_upsert_queries "$WORKFLOWS_DIR/plausible-pull.json")
  [[ "$queries" == *'$1'* ]]
}

@test "github-pull.json: uses positional parameters in query" {
  queries=$(get_upsert_queries "$WORKFLOWS_DIR/github-pull.json")
  [[ "$queries" == *'$1'* ]]
}

@test "bluesky-stream.json: uses positional parameters in query" {
  queries=$(get_upsert_queries "$WORKFLOWS_DIR/bluesky-stream.json")
  [[ "$queries" == *'$1'* ]]
}

@test "tiktok-pull.json: uses positional parameters in query" {
  queries=$(get_upsert_queries "$WORKFLOWS_DIR/tiktok-pull.json")
  [[ "$queries" == *'$1'* ]]
}

@test "x-csv-ingest.json: uses positional parameters in query" {
  queries=$(get_upsert_queries "$WORKFLOWS_DIR/x-csv-ingest.json")
  [[ "$queries" == *'$1'* ]]
}

@test "all 6 workflows are valid JSON" {
  for wf in yt-data-api-pull plausible-pull github-pull bluesky-stream tiktok-pull x-csv-ingest; do
    python3 -c "import json; json.load(open('$WORKFLOWS_DIR/${wf}.json'))" \
      || { echo "INVALID JSON: $wf"; false; }
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# WARN 2: weekly-digest cron timezone
# ─────────────────────────────────────────────────────────────────────────────

@test "weekly-digest.json: cron is 0 9 * * 1 (09:00 ART = 12:00 UTC with GENERIC_TIMEZONE set)" {
  cron_expr=$(python3 -c "
import json
with open('$WORKFLOWS_DIR/weekly-digest.json') as f:
    wf = json.load(f)
for node in wf['nodes']:
    for iv in node.get('parameters', {}).get('rule', {}).get('interval', []):
        if iv.get('field') == 'cronExpression':
            print(iv['expression'])
")
  echo "cron: $cron_expr"
  # Must be 09:00 ART — with GENERIC_TIMEZONE=America/Argentina/Buenos_Aires,
  # n8n interprets the cron in that timezone, so 0 9 * * 1 fires at 09:00 ART
  [[ "$cron_expr" == "0 9 * * 1" ]]
}

@test "weekly-digest.json: ISO week JS code does not use naive day-of-year formula" {
  js_code=$(python3 -c "
import json
with open('$WORKFLOWS_DIR/weekly-digest.json') as f:
    wf = json.load(f)
for node in wf['nodes']:
    if node.get('id') == 'prepare-digest-file':
        print(node.get('parameters', {}).get('jsCode', ''))
")
  echo "js: $js_code"
  # Old naive formula: Math.ceil((((now - onejan) / 86400000) + onejan.getDay() + 1) / 7)
  # Must NOT be present
  [[ "$js_code" != *'onejan'* ]]
}

@test "weekly-digest.json is valid JSON" {
  python3 -c "import json; json.load(open('$WORKFLOWS_DIR/weekly-digest.json'))"
}

# ─────────────────────────────────────────────────────────────────────────────
# WARN 5: anomaly detection min-sample guard
# ─────────────────────────────────────────────────────────────────────────────

@test "anomaly-detection.json: query has HAVING COUNT >= 24 guard" {
  query=$(python3 -c "
import json
with open('$WORKFLOWS_DIR/anomaly-detection.json') as f:
    wf = json.load(f)
for node in wf['nodes']:
    params = node.get('parameters', {})
    if 'query' in params:
        print(params['query'])
")
  echo "query: $query"
  # Must contain a minimum sample guard of at least 24
  [[ "$query" == *'COUNT'* ]] && [[ "$query" == *'24'* ]]
}

@test "anomaly-detection.json is valid JSON" {
  python3 -c "import json; json.load(open('$WORKFLOWS_DIR/anomaly-detection.json'))"
}

# ─────────────────────────────────────────────────────────────────────────────
# WARN 6: heredoc injection — Build Write Command uses stdin pipe, not heredoc
# ─────────────────────────────────────────────────────────────────────────────

@test "weekly-digest.json: Build Write Command does not use heredoc DIGEST_EOF" {
  js_code=$(python3 -c "
import json
with open('$WORKFLOWS_DIR/weekly-digest.json') as f:
    wf = json.load(f)
for node in wf['nodes']:
    if node.get('id') == 'build-write-command':
        print(node.get('parameters', {}).get('jsCode', ''))
")
  echo "js: $js_code"
  # Must not contain the vulnerable heredoc marker
  [[ "$js_code" != *'DIGEST_EOF'* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Round 2 NIT: positive assertion that queryParams exists per workflow
# Mutation guard — a future refactor that drops queryParams while keeping
# $1/$2 placeholders would otherwise pass the absence-only tests above.
# ─────────────────────────────────────────────────────────────────────────────

get_query_params() {
  local file="$1"
  python3 -c "
import json
with open('$file') as f:
    wf = json.load(f)
for node in wf.get('nodes', []):
    params = node.get('parameters', {})
    if 'query' in params and node.get('type','') == 'n8n-nodes-base.postgres':
        qp = params.get('additionalFields', {}).get('queryParams', '')
        print(qp)
"
}

@test "yt-data-api-pull.json: queryParams is non-empty" {
  qp=$(get_query_params "$WORKFLOWS_DIR/yt-data-api-pull.json")
  [[ -n "$qp" ]]
  [[ "$qp" == *'$json'* ]]
}

@test "plausible-pull.json: queryParams is non-empty" {
  qp=$(get_query_params "$WORKFLOWS_DIR/plausible-pull.json")
  [[ -n "$qp" ]]
  [[ "$qp" == *'$json'* ]]
}

@test "github-pull.json: queryParams is non-empty" {
  qp=$(get_query_params "$WORKFLOWS_DIR/github-pull.json")
  [[ -n "$qp" ]]
  [[ "$qp" == *'$json'* ]]
}

@test "bluesky-stream.json: queryParams is non-empty" {
  qp=$(get_query_params "$WORKFLOWS_DIR/bluesky-stream.json")
  [[ -n "$qp" ]]
  [[ "$qp" == *'$json'* ]]
}

@test "tiktok-pull.json: queryParams is non-empty" {
  qp=$(get_query_params "$WORKFLOWS_DIR/tiktok-pull.json")
  [[ -n "$qp" ]]
  [[ "$qp" == *'$json'* ]]
}

@test "x-csv-ingest.json: queryParams is non-empty" {
  qp=$(get_query_params "$WORKFLOWS_DIR/x-csv-ingest.json")
  [[ -n "$qp" ]]
  [[ "$qp" == *'$json'* ]]
}

@test "weekly-digest.json: no orphaned write-digest-file node" {
  # Round 2 fix — old writeBinaryFile node was disconnected, removed entirely
  has_orphan=$(python3 -c "
import json
with open('$WORKFLOWS_DIR/weekly-digest.json') as f:
    wf = json.load(f)
for node in wf['nodes']:
    if node.get('id') == 'write-digest-file':
        print('FOUND')
        break
")
  [[ "$has_orphan" != "FOUND" ]]
}
