#!/usr/bin/env bats
# Tests for protection-levels.toml bundle definition [AC-8]

BUNDLE_FILE="${BATS_TEST_DIRNAME}/../../skills/daily-supply-chain-audit/protection-levels.toml"

@test "protection-levels.toml exists" {
  [ -f "$BUNDLE_FILE" ]
}

@test "protection-levels.toml contains all four levels" {
  grep -q '^\[experimental\]' "$BUNDLE_FILE"
  grep -q '^\[sandbox\]' "$BUNDLE_FILE"
  grep -q '^\[staging\]' "$BUNDLE_FILE"
  grep -q '^\[production\]' "$BUNDLE_FILE"
}

@test "experimental level has minReleaseAge = 0d" {
  python3 -c "
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open('$BUNDLE_FILE', 'rb') as f:
    d = tomllib.load(f)
assert d['experimental']['minReleaseAge'] == '0d', f\"got {d['experimental']['minReleaseAge']}\"
"
}

@test "sandbox level has minReleaseAge = 7d" {
  python3 -c "
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open('$BUNDLE_FILE', 'rb') as f:
    d = tomllib.load(f)
assert d['sandbox']['minReleaseAge'] == '7d', f\"got {d['sandbox']['minReleaseAge']}\"
"
}

@test "staging level has minReleaseAge = 14d" {
  python3 -c "
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open('$BUNDLE_FILE', 'rb') as f:
    d = tomllib.load(f)
assert d['staging']['minReleaseAge'] == '14d', f\"got {d['staging']['minReleaseAge']}\"
"
}

@test "production level has minReleaseAge = 21d" {
  python3 -c "
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open('$BUNDLE_FILE', 'rb') as f:
    d = tomllib.load(f)
assert d['production']['minReleaseAge'] == '21d', f\"got {d['production']['minReleaseAge']}\"
"
}

@test "all levels have required keys: minReleaseAge, pinStrategy, auditGate, review" {
  python3 -c "
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open('$BUNDLE_FILE', 'rb') as f:
    d = tomllib.load(f)
required = {'minReleaseAge', 'pinStrategy', 'auditGate', 'review'}
levels = ['experimental', 'sandbox', 'staging', 'production']
for level in levels:
    missing = required - set(d[level].keys())
    assert not missing, f'Level {level} missing keys: {missing}'
"
}
