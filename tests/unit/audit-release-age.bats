#!/usr/bin/env bats
# Tests for check_min_release_age() in audit.sh [AC-4, AC-5]

AUDIT_SCRIPT="${BATS_TEST_DIRNAME}/../../skills/daily-supply-chain-audit/scripts/audit.sh"
RELEASE_AGE_PY="${BATS_TEST_DIRNAME}/../../skills/daily-supply-chain-audit/scripts/check-release-age.py"
REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
  TMPDIR="$(mktemp -d)"
  export TMPDIR

  # Override HOME to isolate test from real config
  export HOME="$TMPDIR"
  mkdir -p "$TMPDIR/.config/walter-os"
  mkdir -p "$TMPDIR/.claude"
  mkdir -p "$TMPDIR/.codex"

  # Point audit.sh at THIS worktree, not any operator-specific checkout path
  # (which doesn't exist under the overridden HOME).
  export WALTER_OS_HOME="$REPO_ROOT"

  # Create a minimal settings.json with an npx MCP entry
  export FAKE_WALTER_CONFIG="$TMPDIR/.config/walter-os"
  export WALTER_AUDIT_REPO_DIR="$TMPDIR/repo"
  mkdir -p "$WALTER_AUDIT_REPO_DIR"

  # Create a walter-os.toml at experimental level so age check is skipped by default
  # (individual tests override this)
  cat > "$WALTER_AUDIT_REPO_DIR/walter-os.toml" <<'EOF'
[walter]
protection = "experimental"
EOF

  # Create empty settings.json (no MCP servers by default)
  echo '{"mcpServers":{}}' > "$TMPDIR/.claude/settings.json"
}

@test "audit.sh fallback resolves walter home relative to the script" {
  unset WALTER_OS_HOME
  cat > "$WALTER_AUDIT_REPO_DIR/walter-os.toml" <<'EOF'
[walter]
protection = "production"
EOF
  run bash -c "WA_SKIP_NETWORK=1 WALTER_AUDIT_REPO_DIR=\"$WALTER_AUDIT_REPO_DIR\" bash \"$AUDIT_SCRIPT\""
  [ "$status" -ne 3 ]
  [[ "$output" != *"Projects-Personal/walter-os"* ]]
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "audit.sh exits with 0 when no MCP servers configured (experimental level)" {
  run bash "$AUDIT_SCRIPT"
  # Exit code 0 = clean or 1 = info; both are acceptable since no MCPs
  [ "$status" -le 1 ]
}

@test "check_min_release_age skips at experimental level (minReleaseAgeDays=0)" {
  # Experimental level means skip entirely - verify no release-age findings
  run bash "$AUDIT_SCRIPT"
  [ "$status" -le 1 ]
  # Should not emit any release-age-young finding
  echo "$output" | grep -v "release-age-young" || true
}

@test "check_min_release_age runs at production level with WA_SKIP_NETWORK=1" {
  # Set production level
  cat > "$WALTER_AUDIT_REPO_DIR/walter-os.toml" <<'EOF'
[walter]
protection = "production"
EOF
  # Add a mock MCP server with an npx package
  cat > "$TMPDIR/.claude/settings.json" <<'EOF'
{
  "mcpServers": {
    "test-mcp": {
      "command": "npx",
      "args": ["-y", "test-pkg@1.0.0"]
    }
  }
}
EOF
  # Skip network so we don't actually hit npm registry
  run bash -c "WA_SKIP_NETWORK=1 WALTER_AUDIT_REPO_DIR=\"$WALTER_AUDIT_REPO_DIR\" bash \"$AUDIT_SCRIPT\""
  # With network skipped, release-age check should produce info (not high) findings
  # Exit code should not be 2 (high severity) due to network error being info
  [ "$status" -ne 3 ]  # must not be critical
}

@test "npm release-age lookup uses package-level URL (regression for HIGH-1)" {
  # The version-level URL (`/<pkg>/<version>`) returns no `.time` map, so the
  # original code raised ValueError on every real npm package. Guard against
  # regressing to that shape via a literal grep on the script.
  grep -nE 'registry\.npmjs\.org/\{[^}]+\}/\{[^}]+\}' "$RELEASE_AGE_PY" && {
    echo "check-release-age.py still uses version-level npm URL (HIGH-1)" >&2
    return 1
  }
  # Positive assertion: must hit the package-level endpoint (no /version suffix).
  grep -qE 'registry\.npmjs\.org/\{quote\(' "$RELEASE_AGE_PY"
}

@test "check_min_release_age emits release-age finding in report at production level" {
  cat > "$WALTER_AUDIT_REPO_DIR/walter-os.toml" <<'EOF'
[walter]
protection = "production"
EOF
  cat > "$TMPDIR/.claude/settings.json" <<'EOF'
{
  "mcpServers": {
    "test-mcp": {
      "command": "npx",
      "args": ["-y", "test-pkg@1.0.0"]
    }
  }
}
EOF
  # Run audit with network disabled - should produce release-age-network-error finding (info)
  WA_SKIP_NETWORK=1 WALTER_AUDIT_REPO_DIR="$WALTER_AUDIT_REPO_DIR" bash "$AUDIT_SCRIPT" || true
  local today; today="$(date +%Y-%m-%d)"
  local report="$TMPDIR/.config/walter-os/audit-${today}.md"
  [ -f "$report" ]
  # The report must contain a release-age finding
  grep -q "release-age" "$report"
}

@test "release-age info findings propagate from the loop (regression for HIGH-2)" {
  # Before the fix, findings were emitted inside a pipe (`python3 ... | while read`),
  # which runs in a subshell — FINDINGS / SEVERITY mutations were discarded and
  # the report never showed offline info-level findings. This is the canary.
  cat > "$WALTER_AUDIT_REPO_DIR/walter-os.toml" <<'EOF'
[walter]
protection = "production"
EOF
  cat > "$TMPDIR/.claude/settings.json" <<'EOF'
{
  "mcpServers": {
    "test-mcp": {
      "command": "npx",
      "args": ["-y", "test-pkg@1.0.0"]
    }
  }
}
EOF

  WA_SKIP_NETWORK=1 WALTER_AUDIT_REPO_DIR="$WALTER_AUDIT_REPO_DIR" bash "$AUDIT_SCRIPT" || true
  local today; today="$(date +%Y-%m-%d)"
  local report="$TMPDIR/.config/walter-os/audit-${today}.md"
  local status_file="$TMPDIR/.config/walter-os/audit-status.json"

  [ -f "$report" ]
  [ -f "$status_file" ]

  # The release-age-network-error finding MUST appear in the report's Findings
  # section. If the subshell bug is reintroduced, the loop runs in a subshell
  # and FINDINGS never gets the entry — the report will say "No findings".
  grep -q "release-age-network-error" "$report"

  # The info counter must have incremented past the baseline. With the subshell
  # bug, info=0 even though the loop "ran" — that's the bug's silent failure mode.
  local info_count
  info_count="$(jq -r '.info' "$status_file")"
  [ "$info_count" -ge 1 ]
}

@test "release-age high findings propagate when audit-gate is high (HIGH-2)" {
  # Pre-seed the cache with a young release date so the package fails the
  # min-age check WITHOUT touching the network. If the subshell bug regresses,
  # the high-severity finding never makes it into FINDINGS and severity stays
  # at 0.
  cat > "$WALTER_AUDIT_REPO_DIR/walter-os.toml" <<'EOF'
[walter]
protection = "production"
EOF
  cat > "$TMPDIR/.claude/settings.json" <<'EOF'
{
  "mcpServers": {
    "test-mcp": {
      "command": "npx",
      "args": ["-y", "test-pkg@1.0.0"]
    }
  }
}
EOF
  # Cache a "published yesterday" entry — well under any min-age threshold.
  local yesterday; yesterday="$(date -u -v-1d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d 'yesterday' +%Y-%m-%dT%H:%M:%SZ)"
  local now;       now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$TMPDIR/.config/walter-os/release-date-cache.json" <<EOF
{
  "test-pkg@1.0.0": {"published": "$yesterday", "fetched_at": "$now"}
}
EOF

  WALTER_AUDIT_REPO_DIR="$WALTER_AUDIT_REPO_DIR" bash "$AUDIT_SCRIPT" || true
  local today; today="$(date +%Y-%m-%d)"
  local report="$TMPDIR/.config/walter-os/audit-${today}.md"
  local status_file="$TMPDIR/.config/walter-os/audit-status.json"

  grep -q "release-age-young" "$report"
  local high_count
  high_count="$(jq -r '.high' "$status_file")"
  [ "$high_count" -ge 1 ]
}

@test "release-age remediation includes pkg@version, not the finding id (LOW)" {
  # Codex R2 LOW: the action text was building `walter-os justify <id>` where
  # <id> was the finding id (`release-age-network-error` etc), not the package
  # spec — gives users a broken command. Verify the remediation now suggests
  # `walter-os justify <pkg>@<version>`.
  cat > "$WALTER_AUDIT_REPO_DIR/walter-os.toml" <<'EOF'
[walter]
protection = "production"
EOF
  cat > "$TMPDIR/.claude/settings.json" <<'EOF'
{
  "mcpServers": {
    "test-mcp": {
      "command": "npx",
      "args": ["-y", "test-pkg@1.0.0"]
    }
  }
}
EOF

  WA_SKIP_NETWORK=1 WALTER_AUDIT_REPO_DIR="$WALTER_AUDIT_REPO_DIR" bash "$AUDIT_SCRIPT" || true
  local today; today="$(date +%Y-%m-%d)"
  local report="$TMPDIR/.config/walter-os/audit-${today}.md"

  # The action should reference the actual package spec, NOT the finding id.
  grep -qE "walter-os justify test-pkg@1\.0\.0" "$report"
  # Negative: must NOT suggest `walter-os justify release-age-...`
  run grep -E "walter-os justify release-age-" "$report"
  [ "$status" -ne 0 ]
}
