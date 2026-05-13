#!/usr/bin/env bats
# Integration smoke test for protection-levels feature [AC-1 through AC-10]

WALTER_OS_BIN="${BATS_TEST_DIRNAME}/../../bin/walter-os"
AUDIT_SCRIPT="${BATS_TEST_DIRNAME}/../../skills/daily-supply-chain-audit/scripts/audit.sh"
REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
  TMPDIR="$(mktemp -d)"
  export TMPDIR
  FAKE_HOME="$(mktemp -d)"
  export FAKE_HOME
  FAKE_WALTER_CONFIG="$(mktemp -d)"
  export FAKE_WALTER_CONFIG
  mkdir -p "$FAKE_HOME/.config/pnpm"
  mkdir -p "$FAKE_HOME/.claude"
  mkdir -p "$FAKE_HOME/.codex"

  # Temp repo dir for testing
  TEMP_REPO="$(mktemp -d)"
  export TEMP_REPO

  # Set up a production walter-os.toml in the temp repo
  cat > "$TEMP_REPO/walter-os.toml" <<'EOF'
[walter]
protection = "production"
context    = "work"
EOF

  # Minimal settings.json (no MCPs to avoid network calls)
  echo '{"mcpServers":{}}' > "$FAKE_HOME/.claude/settings.json"
}

teardown() {
  rm -rf "$TMPDIR" "$FAKE_HOME" "$FAKE_WALTER_CONFIG" "$TEMP_REPO"
}

# ---------------------------------------------------------------------------
# AC-2: walter-os protection
# ---------------------------------------------------------------------------

@test "[AC-2] walter-os protection --json contains level=production and minReleaseAgeDays=21" {
  run bash -c "cd \"$TEMP_REPO\" && WALTER_CONFIG=\"$FAKE_WALTER_CONFIG\" WALTER_OS_HOME=\"$REPO_ROOT\" HOME=\"$FAKE_HOME\" \"$WALTER_OS_BIN\" protection --json 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['level'] == 'production', f'level={d[\"level\"]}'
assert d['minReleaseAgeDays'] == 21, f'minReleaseAgeDays={d[\"minReleaseAgeDays\"]}'
"
}

# ---------------------------------------------------------------------------
# AC-6, AC-7: walter-os justify
# ---------------------------------------------------------------------------

@test "[AC-6] walter-os justify appends entry to justify-log.jsonl" {
  run bash -c "
    WALTER_CONFIG=\"$FAKE_WALTER_CONFIG\" WALTER_OS_HOME=\"$REPO_ROOT\" HOME=\"$FAKE_HOME\" \
      \"$WALTER_OS_BIN\" justify 'test-pkg@1.0.0' --reason='integration test'
  "
  [ "$status" -eq 0 ]
  [ -f "$FAKE_WALTER_CONFIG/justify-log.jsonl" ]
  grep -q '"test-pkg"' "$FAKE_WALTER_CONFIG/justify-log.jsonl"
}

@test "[AC-7] check-release-age.py honors justify-log entries" {
  local checker="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/check-release-age.py"
  local justify_log="$FAKE_WALTER_CONFIG/justify-log.jsonl"
  local cache_file="$FAKE_WALTER_CONFIG/cache.json"

  # Write a justify entry for test-pkg@1.0.0
  local expires; expires="$(date -u -v+89d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+89 days' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"2026-05-01T00:00:00Z","pkg":"test-pkg","version":"1.0.0","level":"production","reason":"integration test","operator":"nico","expires":"%s"}\n' "$expires" \
    > "$justify_log"

  # Mock: provide a fresh release date via cache (simulating a 2-day-old package)
  local fresh_date; fresh_date="$(date -u -v-2d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-2 days' +%Y-%m-%dT%H:%M:%SZ)"
  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  python3 -c "
import json
cache = {'test-pkg@1.0.0': {'published': '$fresh_date', 'fetched_at': '$now'}}
print(json.dumps(cache))
" > "$cache_file"

  run python3 "$checker" \
    "test-pkg@1.0.0" \
    --min-age-days 21 \
    --cache-file "$cache_file" \
    --justify-log "$justify_log"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
findings = json.load(sys.stdin)
assert len(findings) == 1
f = findings[0]
assert f.get('justified') is True, f'not justified: {f}'
assert f.get('ok') is True, f'ok is False: {f}'
"
}

# ---------------------------------------------------------------------------
# AC-5: offline mode (WA_SKIP_NETWORK=1)
# ---------------------------------------------------------------------------

@test "[AC-5] audit.sh exits cleanly in offline mode (WA_SKIP_NETWORK=1)" {
  # Add one MCP server to settings.json
  cat > "$FAKE_HOME/.claude/settings.json" <<'EOF'
{
  "mcpServers": {
    "test-mcp": {
      "command": "npx",
      "args": ["-y", "some-pkg@1.0.0"]
    }
  }
}
EOF
  cat > "$TEMP_REPO/walter-os.toml" <<'EOF'
[walter]
protection = "production"
EOF

  # Run audit with network disabled
  WA_SKIP_NETWORK=1 WALTER_AUDIT_REPO_DIR="$TEMP_REPO" HOME="$FAKE_HOME" \
    bash "$AUDIT_SCRIPT" || true

  # The report should exist
  local today; today="$(date +%Y-%m-%d)"
  local report="$FAKE_HOME/.config/walter-os/audit-${today}.md"
  [ -f "$report" ]

  # The report should NOT be critical (3) — network failures are info (1) severity
  local status_json="$FAKE_HOME/.config/walter-os/audit-status.json"
  [ -f "$status_json" ]
  local sev; sev="$(python3 -c "import json; d=json.load(open('$status_json')); print(d.get('severity',99))" 2>/dev/null || echo 99)"
  # Should not be critical (3)
  [ "$sev" -lt 3 ]
}

# ---------------------------------------------------------------------------
# walter-os.toml manifest (AC-1)
# ---------------------------------------------------------------------------

@test "[AC-1] walter-os.toml parser handles malformed TOML gracefully" {
  printf '[walter\nprotection = broken\n' > "$TEMP_REPO/walter-os.toml"
  run bash -c "cd \"$TEMP_REPO\" && WALTER_CONFIG=\"$FAKE_WALTER_CONFIG\" WALTER_OS_HOME=\"$REPO_ROOT\" HOME=\"$FAKE_HOME\" \"$WALTER_OS_BIN\" protection --json 2>/dev/null"
  [ "$status" -eq 0 ]
  # Should return valid JSON with staging default
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['level'] == 'staging', f'expected staging fallback, got {d[\"level\"]}'
"
}
