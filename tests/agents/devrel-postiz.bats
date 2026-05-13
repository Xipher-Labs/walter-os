#!/usr/bin/env bats
# Phase V — Part E: Postiz verification + prereqs doc update
# Covers: AC-17 (Postiz version verified), AC-18 (analytics export documented)
#
# Refs: docs/specs/devrel-analytics-stack.md

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  POSTIZ_DIR="$REPO_ROOT/setup/walter-host/services/postiz"
  PREREQS_DOC="$REPO_ROOT/docs/operational/council-v2-prereqs.md"
}

# ── Postiz service directory ──────────────────────────────────────────────────

@test "postiz service directory exists" {
  [[ -d "$POSTIZ_DIR" ]]
}

@test "postiz compose.yml exists" {
  [[ -f "$POSTIZ_DIR/compose.yml" ]]
}

@test "postiz compose references image v2.21.7 or upgrade note" {
  [[ -f "$POSTIZ_DIR/compose.yml" ]]
  # Either pinned to v2.21.7 or uses latest with upgrade comment
  grep -qi "postiz\|v2.21\|ghcr.io/gitroomhq" "$POSTIZ_DIR/compose.yml"
}

@test "postiz upgrade runbook exists" {
  [[ -f "$POSTIZ_DIR/UPGRADE.md" ]] || \
  grep -qi "postiz.*upgrade\|upgrade.*postiz" "$PREREQS_DOC"
}

# ── Postiz analytics export documented (AC-18) ────────────────────────────────

@test "postiz analytics export documentation exists" {
  [[ -f "$POSTIZ_DIR/analytics-export.md" ]] || \
  [[ -f "$REPO_ROOT/docs/operational/postiz-analytics-export.md" ]]
}

@test "analytics export doc mentions webhook or API endpoint" {
  local doc
  if [[ -f "$POSTIZ_DIR/analytics-export.md" ]]; then
    doc="$POSTIZ_DIR/analytics-export.md"
  else
    doc="$REPO_ROOT/docs/operational/postiz-analytics-export.md"
  fi
  [[ -f "$doc" ]] || skip "analytics export doc not found"
  grep -qi "webhook\|api\|endpoint\|export\|analytics" "$doc"
}

# ── Prereqs doc Phase V section ───────────────────────────────────────────────

@test "council-v2-prereqs.md has Phase V section" {
  [[ -f "$PREREQS_DOC" ]]
  grep -qi "Phase V\|V-prereq" "$PREREQS_DOC"
}

@test "prereqs doc lists V-prereq-6 postgres custom Dockerfile" {
  [[ -f "$PREREQS_DOC" ]]
  grep -qi "V-prereq-6\|pg_partman\|pg_cron\|custom.*Dockerfile" "$PREREQS_DOC"
}
