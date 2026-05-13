#!/usr/bin/env bats
# Tests for 'walter-os protection' subcommand [AC-2]

WALTER_OS_BIN="${BATS_TEST_DIRNAME}/../../bin/walter-os"
PARSER="${BATS_TEST_DIRNAME}/../../scripts/parse-manifest.py"
BUNDLES="${BATS_TEST_DIRNAME}/../../skills/daily-supply-chain-audit/protection-levels.toml"

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
  TMPDIR="$(mktemp -d)"
  export TMPDIR
  # Create a minimal WALTER_CONFIG dir without an env file
  # so WALTER_OS_HOME is not overridden by the installed walter-os env
  FAKE_WALTER_CONFIG="$(mktemp -d)"
  export FAKE_WALTER_CONFIG
}

teardown() {
  rm -rf "$TMPDIR" "$FAKE_WALTER_CONFIG"
}

@test "no manifest in temp dir prints auto-assigned level, exits 0" {
  run bash -c "cd \"$TMPDIR\" && WALTER_CONFIG=\"$FAKE_WALTER_CONFIG\" WALTER_OS_HOME=\"$REPO_ROOT\" \"$WALTER_OS_BIN\" protection 2>/dev/null"
  [ "$status" -eq 0 ]
  # Should contain "Protection level:" line
  echo "$output" | grep -q "Protection level:"
}

@test "manifest with sandbox level prints sandbox" {
  cat > "$TMPDIR/walter-os.toml" <<'EOF'
[walter]
protection = "sandbox"
EOF
  run bash -c "cd \"$TMPDIR\" && WALTER_CONFIG=\"$FAKE_WALTER_CONFIG\" WALTER_OS_HOME=\"$REPO_ROOT\" \"$WALTER_OS_BIN\" protection 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "sandbox"
}

@test "--json flag emits valid JSON" {
  cat > "$TMPDIR/walter-os.toml" <<'EOF'
[walter]
protection = "staging"
EOF
  run bash -c "cd \"$TMPDIR\" && WALTER_CONFIG=\"$FAKE_WALTER_CONFIG\" WALTER_OS_HOME=\"$REPO_ROOT\" \"$WALTER_OS_BIN\" protection --json 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); assert 'level' in d"
}
