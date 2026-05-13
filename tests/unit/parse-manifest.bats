#!/usr/bin/env bats
# Tests for scripts/parse-manifest.py [AC-1, AC-2]

PARSER="${BATS_TEST_DIRNAME}/../../scripts/parse-manifest.py"
BUNDLES="${BATS_TEST_DIRNAME}/../../skills/daily-supply-chain-audit/protection-levels.toml"

setup() {
  TMPDIR="$(mktemp -d)"
  export TMPDIR
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "missing manifest auto-assigns by path, exits 0" {
  run bash -c "python3 \"$PARSER\" --repo-dir \"$TMPDIR\" --bundles-file \"$BUNDLES\" 2>/dev/null"
  [ "$status" -eq 0 ]
  # Should emit valid JSON
  echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'level' in d"
}

@test "manifest with production level resolves correctly" {
  cat > "$TMPDIR/walter-os.toml" <<'EOF'
[walter]
protection = "production"
EOF
  run python3 "$PARSER" \
    --repo-dir "$TMPDIR" \
    --bundles-file "$BUNDLES"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['level'] == 'production', f'got {d[\"level\"]}'
assert d['minReleaseAge'] == '21d', f'got {d[\"minReleaseAge\"]}'
assert d['minReleaseAgeDays'] == 21, f'got {d[\"minReleaseAgeDays\"]}'
assert d['pinStrategy'] == 'exact', f'got {d[\"pinStrategy\"]}'
"
}

@test "manifest with overrides applies override" {
  cat > "$TMPDIR/walter-os.toml" <<'EOF'
[walter]
protection = "production"

[walter.overrides]
minReleaseAge = "3d"
EOF
  run python3 "$PARSER" \
    --repo-dir "$TMPDIR" \
    --bundles-file "$BUNDLES"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['level'] == 'production', f'got {d[\"level\"]}'
assert d['minReleaseAge'] == '3d', f'override not applied, got {d[\"minReleaseAge\"]}'
assert d['minReleaseAgeDays'] == 3, f'got {d[\"minReleaseAgeDays\"]}'
"
}

@test "malformed TOML emits warning on stderr, uses staging default, exits 0" {
  printf '[walter\nprotection = "broken"\n' > "$TMPDIR/walter-os.toml"
  # Capture stderr separately to verify the warning is there
  stderr_file="$TMPDIR/stderr.txt"
  run bash -c "python3 \"$PARSER\" --repo-dir \"$TMPDIR\" --bundles-file \"$BUNDLES\" 2>\"$stderr_file\""
  [ "$status" -eq 0 ]
  # Stdout should be valid JSON with staging defaults
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['level'] == 'staging', f'expected staging fallback, got {d[\"level\"]}'
"
  # Stderr should contain a warning
  grep -qi "warning\|malformed" "$stderr_file"
}

@test "experimental level resolves minReleaseAgeDays to 0" {
  cat > "$TMPDIR/walter-os.toml" <<'EOF'
[walter]
protection = "experimental"
EOF
  run python3 "$PARSER" \
    --repo-dir "$TMPDIR" \
    --bundles-file "$BUNDLES"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['level'] == 'experimental', f'got {d[\"level\"]}'
assert d['minReleaseAgeDays'] == 0, f'got {d[\"minReleaseAgeDays\"]}'
"
}
