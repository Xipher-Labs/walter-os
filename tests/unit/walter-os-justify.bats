#!/usr/bin/env bats
# Tests for 'walter-os justify' subcommand [AC-6, AC-7]

WALTER_OS_BIN="${BATS_TEST_DIRNAME}/../../bin/walter-os"
REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
  TMPDIR="$(mktemp -d)"
  export TMPDIR
  # Use a fake WALTER_CONFIG so logs go to temp dir
  FAKE_WALTER_CONFIG="$(mktemp -d)"
  export FAKE_WALTER_CONFIG
  # Use a fake HOME that doesn't have the real env file
  FAKE_HOME="$(mktemp -d)"
  export FAKE_HOME
}

teardown() {
  rm -rf "$TMPDIR" "$FAKE_WALTER_CONFIG" "$FAKE_HOME"
}

_run_justify() {
  WALTER_CONFIG="$FAKE_WALTER_CONFIG" WALTER_OS_HOME="$REPO_ROOT" HOME="$FAKE_HOME" "$WALTER_OS_BIN" justify "$@"
}

@test "successful justify appends entry to log file, exits 0" {
  run bash -c "WALTER_CONFIG=\"$FAKE_WALTER_CONFIG\" WALTER_OS_HOME=\"$REPO_ROOT\" HOME=\"$FAKE_HOME\" \"$WALTER_OS_BIN\" justify lodash@4.17.21 --reason='critical security patch needed now'"
  [ "$status" -eq 0 ]
  # Log file should exist
  [ -f "$FAKE_WALTER_CONFIG/justify-log.jsonl" ]
  # Log should contain the pkg entry
  grep -q '"pkg"' "$FAKE_WALTER_CONFIG/justify-log.jsonl"
  grep -q '"lodash"' "$FAKE_WALTER_CONFIG/justify-log.jsonl"
}

@test "missing --reason exits 2 and does not write entry" {
  run bash -c "WALTER_CONFIG=\"$FAKE_WALTER_CONFIG\" WALTER_OS_HOME=\"$REPO_ROOT\" HOME=\"$FAKE_HOME\" \"$WALTER_OS_BIN\" justify lodash@4.17.21 2>/dev/null"
  [ "$status" -eq 2 ]
  # Log file should not exist (no entry written)
  [ ! -f "$FAKE_WALTER_CONFIG/justify-log.jsonl" ]
}

@test "justify list shows non-expired entries" {
  # First, create an entry
  WALTER_CONFIG="$FAKE_WALTER_CONFIG" WALTER_OS_HOME="$REPO_ROOT" HOME="$FAKE_HOME" \
    "$WALTER_OS_BIN" justify react@18.0.0 --reason="integration test" >/dev/null 2>&1

  run bash -c "WALTER_CONFIG=\"$FAKE_WALTER_CONFIG\" WALTER_OS_HOME=\"$REPO_ROOT\" HOME=\"$FAKE_HOME\" \"$WALTER_OS_BIN\" justify list"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "react@18.0.0"
}

@test "expired entry not shown in list" {
  # Write an already-expired entry directly to the log
  local yesterday; yesterday="$(date -u -v-1d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-1 day' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"2026-01-01T00:00:00Z","pkg":"old-pkg","version":"0.0.1","level":"production","reason":"old reason","operator":"nico","expires":"%s"}\n' "$yesterday" \
    >> "$FAKE_WALTER_CONFIG/justify-log.jsonl"

  run bash -c "WALTER_CONFIG=\"$FAKE_WALTER_CONFIG\" WALTER_OS_HOME=\"$REPO_ROOT\" HOME=\"$FAKE_HOME\" \"$WALTER_OS_BIN\" justify list"
  [ "$status" -eq 0 ]
  # Should NOT show the expired entry
  ! echo "$output" | grep -q "old-pkg"
}

# ---- M8: justify JSONL append must be lock-protected ----
#
# Codex R2 MEDIUM M8: `cat $tmp_line >> $log_file` is not a guaranteed
# atomic append on POSIX. Concurrent `walter-os justify` invocations can
# interleave bytes and produce truncated / mixed lines. With flock the
# append is serialised and every entry survives intact.

@test "M8: justify append uses flock-protected write (source check)" {
  # The fix must register a file lock around the JSONL append. We do not
  # rely on `flock` being on PATH (macOS doesn't ship it) — the bash
  # alternative is a `mkdir`-based lock or a Python `fcntl.flock` helper.
  # This test pins one of those patterns into the source so the protection
  # cannot be quietly removed.
  if ! grep -qE 'flock|fcntl|mkdir.*\.lock' "$WALTER_OS_BIN"; then
    echo "no lock mechanism found in walter-os justify path"
    grep -n 'justify' "$WALTER_OS_BIN" | head -20
    return 1
  fi
}

@test "M8: 30 concurrent justify invocations produce 30 intact JSONL entries (no interleaving)" {
  # Each reason is intentionally large (~4KB) to push `cat tmp >> log`
  # past single-write atomicity on small file systems. The serialisation
  # the fix introduces (flock) is what guarantees no interleaving
  # regardless of write size.
  local big_reason; big_reason="$(printf 'A%.0s' {1..2000})"
  N=30
  pids=()
  for i in $(seq 1 $N); do
    (
      WALTER_CONFIG="$FAKE_WALTER_CONFIG" \
      WALTER_OS_HOME="$REPO_ROOT" \
      HOME="$FAKE_HOME" \
        "$WALTER_OS_BIN" justify "pkg${i}@1.0.0" --reason="${big_reason}-marker${i}-${big_reason}" \
        >/dev/null 2>&1
    ) &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p"; done

  log="$FAKE_WALTER_CONFIG/justify-log.jsonl"
  [ -f "$log" ]

  # Line count must equal N (no truncation, no concatenation)
  line_count="$(wc -l < "$log" | tr -d ' ')"
  if [ "$line_count" -ne "$N" ]; then
    echo "line count mismatch: got=${line_count} expected=${N}"
    return 1
  fi

  # Every line must be valid JSON
  python3 -c "
import json, sys
ok = 0
bad = []
with open('$log') as fh:
    for i, line in enumerate(fh, 1):
        line = line.strip()
        if not line:
            continue
        try:
            json.loads(line)
            ok += 1
        except Exception as e:
            bad.append((i, str(e), line[:200]))
if bad:
    sys.stderr.write(f'corrupt lines: {bad}\n')
    sys.exit(1)
print(f'all {ok} lines parsed as JSON', file=sys.stderr)
" || return 1

  # Every pkg name must be present exactly once
  for i in $(seq 1 $N); do
    count="$(grep -c "\"pkg${i}\"" "$log" || true)"
    if [ "$count" -ne 1 ]; then
      echo "pkg${i}: count=${count} (expected 1)"
      return 1
    fi
  done
}
