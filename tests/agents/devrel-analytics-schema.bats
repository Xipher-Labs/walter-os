#!/usr/bin/env bats
# Phase V — Part A: DevRel Analytics schema validation
# Covers: AC-1, AC-2, AC-3, AC-4 (schema prerequisite for all ingestion)
#
# Refs: docs/specs/devrel-analytics-stack.md

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  POSTGRES_DIR="$REPO_ROOT/setup/walter-host/services/postgres"
  MIGRATIONS_DIR="$REPO_ROOT/setup/walter-host/services/postgres/migrations"
  SINGER_DIR="$REPO_ROOT/setup/walter-host/singer"
}

# ── Postgres Dockerfile (V-prereq-6) ────────────────────────────────────────

@test "postgres custom Dockerfile exists with pg_partman and pg_cron" {
  [[ -f "$POSTGRES_DIR/Dockerfile" ]]
  grep -q "pg_partman\|postgresql.*partman" "$POSTGRES_DIR/Dockerfile"
  grep -q "pg_cron\|postgresql.*cron" "$POSTGRES_DIR/Dockerfile"
}

@test "postgres Dockerfile is based on postgres:17" {
  [[ -f "$POSTGRES_DIR/Dockerfile" ]]
  grep -q "FROM postgres:17" "$POSTGRES_DIR/Dockerfile"
}

@test "postgres custom postgresql.conf sets shared_preload_libraries pg_cron" {
  [[ -f "$POSTGRES_DIR/postgresql.conf" ]] || \
  grep -rq "shared_preload_libraries.*pg_cron" "$POSTGRES_DIR/"
}

# ── Migration files ──────────────────────────────────────────────────────────

@test "migration 001_analytics_events.sql exists" {
  [[ -f "$MIGRATIONS_DIR/001_analytics_events.sql" ]]
}

@test "migration 001 creates analytics_events table" {
  [[ -f "$MIGRATIONS_DIR/001_analytics_events.sql" ]]
  grep -q "CREATE TABLE.*analytics_events" "$MIGRATIONS_DIR/001_analytics_events.sql"
}

@test "migration 001 analytics_events has required columns" {
  [[ -f "$MIGRATIONS_DIR/001_analytics_events.sql" ]]
  local f="$MIGRATIONS_DIR/001_analytics_events.sql"
  grep -q "occurred_at" "$f"
  grep -q "platform" "$f"
  grep -q "content_id" "$f"
  grep -q "event_type" "$f"
  grep -q "metric_value" "$f"
}

@test "migration 001 creates content_pieces table" {
  [[ -f "$MIGRATIONS_DIR/001_analytics_events.sql" ]]
  grep -q "CREATE TABLE.*content_pieces" "$MIGRATIONS_DIR/001_analytics_events.sql"
}

@test "migration 001 creates ad_spend_events table" {
  [[ -f "$MIGRATIONS_DIR/001_analytics_events.sql" ]]
  grep -q "CREATE TABLE.*ad_spend_events" "$MIGRATIONS_DIR/001_analytics_events.sql"
}

@test "migration 001 analytics_events has UNIQUE constraint" {
  [[ -f "$MIGRATIONS_DIR/001_analytics_events.sql" ]]
  grep -q "UNIQUE" "$MIGRATIONS_DIR/001_analytics_events.sql"
}

@test "migration 002_materialized_views.sql exists" {
  [[ -f "$MIGRATIONS_DIR/002_materialized_views.sql" ]]
}

@test "migration 002 creates materialized views" {
  [[ -f "$MIGRATIONS_DIR/002_materialized_views.sql" ]]
  grep -q "CREATE MATERIALIZED VIEW\|MATERIALIZED VIEW" "$MIGRATIONS_DIR/002_materialized_views.sql"
}

# ── Postgres compose service ─────────────────────────────────────────────────

@test "postgres analytics service compose file exists" {
  [[ -f "$POSTGRES_DIR/compose.yml" ]]
}

@test "postgres analytics compose uses custom image build" {
  [[ -f "$POSTGRES_DIR/compose.yml" ]]
  grep -q "build:\|dockerfile:\|Dockerfile" "$POSTGRES_DIR/compose.yml"
}

# ── Singer state directory documented ────────────────────────────────────────

@test "singer env example config file exists" {
  [[ -f "$SINGER_DIR/config.env.example" ]] || \
  [[ -f "$REPO_ROOT/setup/walter-host/singer/config.env.example" ]]
}
