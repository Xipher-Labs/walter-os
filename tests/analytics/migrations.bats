#!/usr/bin/env bats
# Tests for Postgres migration files
#
# Covers:
#   WARN 1  — content_pieces.platform generated column exists in migration
#   WARN 3  — ad_id NOT NULL in ad_spend_events
#   NIT 1   — analytics_events PRIMARY KEY includes partition key (occurred_at)
#
# These are static analysis tests on the SQL files (no live DB required).
#
# Refs: docs/specs/devrel-analytics-stack.md

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
MIGRATIONS_DIR="${REPO_ROOT}/setup/walter-host/services/postgres/migrations"

# ─────────────────────────────────────────────────────────────────────────────
# WARN 1: content_pieces.platform generated column
# ─────────────────────────────────────────────────────────────────────────────

@test "migration adds platform generated column to content_pieces" {
  # Either migration 001 or 002 should declare the generated column
  grep -q "platform.*GENERATED" "$MIGRATIONS_DIR/001_analytics_events.sql" \
    || grep -q "platform.*GENERATED" "$MIGRATIONS_DIR/002_materialized_views.sql"
}

@test "platform generated column uses split_part on id" {
  grep -qE "split_part\(id" "$MIGRATIONS_DIR/001_analytics_events.sql" \
    || grep -qE "split_part\(id" "$MIGRATIONS_DIR/002_materialized_views.sql"
}

# ─────────────────────────────────────────────────────────────────────────────
# WARN 3: ad_id NOT NULL
# ─────────────────────────────────────────────────────────────────────────────

@test "ad_spend_events.ad_id is declared NOT NULL" {
  grep -q "ad_id.*NOT NULL" "$MIGRATIONS_DIR/001_analytics_events.sql"
}

# ─────────────────────────────────────────────────────────────────────────────
# NIT 1: analytics_events PRIMARY KEY includes occurred_at (partition key)
# ─────────────────────────────────────────────────────────────────────────────

@test "analytics_events PRIMARY KEY includes occurred_at" {
  # The PK must be composite and include occurred_at
  grep -qE "PRIMARY KEY.*occurred_at|occurred_at.*PRIMARY KEY" "$MIGRATIONS_DIR/001_analytics_events.sql"
}

@test "analytics_events does not have a standalone BIGSERIAL PRIMARY KEY" {
  # analytics_events is a partitioned table; inline PK on id alone would fail at runtime.
  # After fix: id BIGSERIAL (no inline PK); composite PK (id, occurred_at) declared separately.
  # ad_spend_events legitimately uses BIGSERIAL PRIMARY KEY (not partitioned), so we scope the
  # check to the analytics_events table block only.
  block=$(awk '/CREATE TABLE IF NOT EXISTS analytics_events/,/PARTITION BY RANGE/' \
    "$MIGRATIONS_DIR/001_analytics_events.sql")
  echo "$block" | grep -qE "id\s+BIGSERIAL\s+PRIMARY KEY" && return 1 || return 0
}
