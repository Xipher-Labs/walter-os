#!/usr/bin/env bats
# tests/walter/audit-chain-append.bats
#
# OSS Trust B-1 audit-chain writer coverage.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT_LIB="$REPO_ROOT/scripts/walter/lib/audit-chain.sh"
  TMP_HOME="$(mktemp -d "$REPO_ROOT/.tmp-audit-chain.XXXXXX")"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/home/.config/walter-os"
  export WALTER_AUDIT_DATE="2026-05-31"
  export WALTER_AUDIT_NOW="2026-05-31T12:00:00Z"
  export WALTER_SESSION_ID="session-test"
  export WALTER_OS_HOME="$REPO_ROOT"
  mkdir -p "$WALTER_CONFIG"
}

teardown() {
  [[ -n "${TMP_HOME:-}" ]] || return 0
  case "$TMP_HOME" in
    "$REPO_ROOT"/.tmp-audit-chain.*) rm -rf "$TMP_HOME" ;;
  esac
}

_chain_path() {
  printf '%s/audit/chain-2026-05-31.jsonl\n' "$WALTER_CONFIG"
}

_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  fi
}

_verify_chain() {
  local file="$1" prev="null" line actual row=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    row=$((row + 1))
    actual="$(printf '%s' "$line" | jq -r '.prev_hash')"
    if [[ "$actual" != "$prev" ]]; then
      echo "row ${row}: expected ${prev}, got ${actual}" >&2
      return 1
    fi
    prev="$(_sha256 "$line")"
  done < "$file"
}

@test "B-1: first append creates chain with null prev_hash" {
  run bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'cat README.md' allow approval-gate 'standing approval'"

  [ "$status" -eq 0 ]
  [ "$output" = "$(_chain_path)" ]
  [ -f "$(_chain_path)" ]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "1" ]
  jq -e '.prev_hash == "null"' "$(_chain_path)"
  jq -e '.tool == "Bash" and .decision == "allow" and .decision_source == "approval-gate"' "$(_chain_path)"
}

@test "B-1: second append chains to first normalized row" {
  bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'cat README.md' allow approval-gate ok >/dev/null"
  first="$(sed -n '1p' "$(_chain_path)")"
  expected="$(_sha256 "$first")"

  run bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'rm -rf /tmp/nope' block bash-denylist destructive"

  [ "$status" -eq 0 ]
  [ "$(sed -n '2p' "$(_chain_path)" | jq -r '.prev_hash')" = "$expected" ]
  _verify_chain "$(_chain_path)"
}

@test "B-1: concurrent appenders serialize with sidecar lock" {
  run bash -c "
    source '$AUDIT_LIB'
    pids=()
    for i in \$(seq 1 12); do
      WALTER_AUDIT_NOW=\"2026-05-31T12:00:\${i}Z\" WALTER_AUDIT_LOCK_WAIT_SECONDS=30 walter_audit_append Bash \"cmd-\${i}\" allow approval-gate ok >/dev/null &
      pids+=(\"\$!\")
    done
    status=0
    for pid in \"\${pids[@]}\"; do
      wait \"\$pid\" || status=1
    done
    exit \"\$status\"
  "

  [ "$status" -eq 0 ]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "12" ]
  _verify_chain "$(_chain_path)"
}

@test "B-1: append after rotation lands in active post-rotation file" {
  bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'before rotation' allow approval-gate ok >/dev/null"
  mv "$(_chain_path)" "$(_chain_path).rotated"

  run bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'after rotation' allow approval-gate ok"

  [ "$status" -eq 0 ]
  [ -f "$(_chain_path)" ]
  [ -f "$(_chain_path).rotated" ]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "1" ]
  jq -e '.prev_hash == "null" and .input_summary == "after rotation"' "$(_chain_path)"
}

@test "B-1: append retries if active chain rotates after open" {
  bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'before rotation' allow approval-gate ok >/dev/null"
  mkdir -p "$TMP_HOME/rotating-redactor/scripts"
  cat > "$TMP_HOME/rotating-redactor/scripts/agent-secret-redactor.sh" <<'SH'
#!/usr/bin/env bash
if [[ -n "${CHAIN_PATH:-}" && -f "$CHAIN_PATH" && ! -f "${CHAIN_PATH}.rotated-during-redaction" ]]; then
  mv "$CHAIN_PATH" "${CHAIN_PATH}.rotated-during-redaction"
fi
cat
SH
  chmod +x "$TMP_HOME/rotating-redactor/scripts/agent-secret-redactor.sh"

  run bash -c "source '$AUDIT_LIB'; WALTER_OS_HOME='$TMP_HOME/rotating-redactor' CHAIN_PATH='$(_chain_path)' walter_audit_append Bash 'after active rotation' allow approval-gate ok"

  [ "$status" -eq 0 ]
  [ -f "$(_chain_path)" ]
  [ -f "$(_chain_path).rotated-during-redaction" ]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "1" ]
  jq -e '.prev_hash == "null" and .input_summary == "after active rotation"' "$(_chain_path)"
}

@test "B-1: active flock lock blocks competing append until timeout" {
  command -v flock >/dev/null 2>&1 || skip "flock not installed"
  mkdir -p "$WALTER_CONFIG/audit"
  lock_file="$WALTER_CONFIG/audit/.chain.lock"

  run bash -c "
    exec 7>'$lock_file'
    flock -x 7
    source '$AUDIT_LIB'
    WALTER_AUDIT_LOCK_WAIT_SECONDS=0 walter_audit_append Bash 'after active lock' allow approval-gate ok
  "

  [ "$status" -ne 0 ]
  [ ! -f "$(_chain_path)" ]
}

@test "B-1: input summaries are single-line and capped" {
  long_input="$(printf 'x%.0s' {1..240})"

  run bash -c "source '$AUDIT_LIB'; walter_audit_append Bash \$'first\\nsecond\\t$long_input' allow approval-gate ok"

  [ "$status" -eq 0 ]
  summary="$(jq -r '.input_summary' "$(_chain_path)")"
  [[ "$summary" != *$'\n'* ]]
  [ "${#summary}" -eq 200 ]
}

@test "B-1: input summaries are redacted before logging" {
  secret="Authorization: Bearer abcdefghijklmnopqrstuvwxyz1234567890"

  run bash -c "source '$AUDIT_LIB'; walter_audit_append Bash '$secret' allow approval-gate ok"

  [ "$status" -eq 0 ]
  summary="$(jq -r '.input_summary' "$(_chain_path)")"
  [[ "$summary" == *"<REDACTED:bearer>"* ]]
  [[ "$summary" != *"abcdefghijklmnopqrstuvwxyz1234567890"* ]]
}

@test "B-1: redactor failures do not log raw input" {
  mkdir -p "$TMP_HOME/failing-redactor/scripts"
  cat > "$TMP_HOME/failing-redactor/scripts/agent-secret-redactor.sh" <<'SH'
#!/usr/bin/env bash
exit 42
SH
  chmod +x "$TMP_HOME/failing-redactor/scripts/agent-secret-redactor.sh"
  secret="Authorization: Bearer abcdefghijklmnopqrstuvwxyz1234567890"

  run bash -c "source '$AUDIT_LIB'; WALTER_OS_HOME='$TMP_HOME/failing-redactor' walter_audit_append Bash '$secret' allow approval-gate ok"

  [ "$status" -eq 0 ]
  summary="$(jq -r '.input_summary' "$(_chain_path)")"
  [ "$summary" = "<REDACTED:redactor-error>" ]
  [[ "$summary" != *"abcdefghijklmnopqrstuvwxyz1234567890"* ]]
}

@test "B-1: missing redactor does not log raw input" {
  mkdir -p "$TMP_HOME/no-redactor/scripts/walter/lib"
  cp "$AUDIT_LIB" "$TMP_HOME/no-redactor/scripts/walter/lib/audit-chain.sh"
  local isolated_lib="$TMP_HOME/no-redactor/scripts/walter/lib/audit-chain.sh"
  secret="Authorization: Bearer abcdefghijklmnopqrstuvwxyz1234567890"

  run bash -c "source '$isolated_lib'; WALTER_OS_HOME='$TMP_HOME/no-redactor' walter_audit_append Bash '$secret' allow approval-gate ok"

  [ "$status" -eq 0 ]
  summary="$(jq -r '.input_summary' "$(_chain_path)")"
  [ "$summary" = "<REDACTED:redactor-unavailable>" ]
  [[ "$summary" != *"abcdefghijklmnopqrstuvwxyz1234567890"* ]]
}

@test "B-1: dependency failure rows append without jq" {
  mkdir -p "$TMP_HOME/mock-bin"
  cat > "$TMP_HOME/mock-bin/jq" <<'SH'
#!/usr/bin/env bash
exit 42
SH
  chmod +x "$TMP_HOME/mock-bin/jq"

  run bash -c "source '$AUDIT_LIB'; PATH='$TMP_HOME/mock-bin:/usr/bin:/bin' walter_audit_append Bash 'jq missing input' block approval-gate 'jq missing'"

  [ "$status" -eq 0 ]
  [ -f "$(_chain_path)" ]
  jq -e '.decision == "block" and .decision_source == "approval-gate" and .decision_reason == "jq missing"' "$(_chain_path)"
}

@test "B-1: dependency failure rows escape JSON controls without jq" {
  mkdir -p "$TMP_HOME/mock-bin"
  cat > "$TMP_HOME/mock-bin/jq" <<'SH'
#!/usr/bin/env bash
exit 42
SH
  chmod +x "$TMP_HOME/mock-bin/jq"

  run bash -c "source '$AUDIT_LIB'; PATH='$TMP_HOME/mock-bin:/usr/bin:/bin' walter_audit_append Bash \$'escape\\e\\a\\b\\\\quote\"' block approval-gate \$'bad\\e\\a\\b reason'"

  [ "$status" -eq 0 ]
  [ -f "$(_chain_path)" ]
  jq -e '.decision == "block" and .decision_reason == ("bad" + "\u001b" + "\u0007" + "\b" + " reason")' "$(_chain_path)"
}

@test "B-1: custom audit dir is honored" {
  custom="$TMP_HOME/custom-audit"

  run bash -c "source '$AUDIT_LIB'; WALTER_AUDIT_DIR='$custom' walter_audit_append Bash ls allow approval-gate ok"

  [ "$status" -eq 0 ]
  [ "$output" = "$custom/chain-2026-05-31.jsonl" ]
  [ -f "$custom/chain-2026-05-31.jsonl" ]
}

@test "B-1: append rejects chain with blank final row" {
  bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'cat README.md' allow approval-gate ok >/dev/null"
  printf '\n' >> "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'after blank row' allow approval-gate ok"

  [ "$status" -eq 1 ]
  [[ "$output" == *"blank final row"* ]]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "2" ]
}

@test "B-1: chain path date follows captured row timestamp" {
  run bash -c "source '$AUDIT_LIB'; WALTER_AUDIT_DATE='2026-05-30' WALTER_AUDIT_NOW='2026-05-31T00:00:01Z' walter_audit_append Bash midnight allow approval-gate ok"

  [ "$status" -eq 0 ]
  [ "$output" = "$WALTER_CONFIG/audit/chain-2026-05-31.jsonl" ]
  [ -f "$WALTER_CONFIG/audit/chain-2026-05-31.jsonl" ]
  [ ! -f "$WALTER_CONFIG/audit/chain-2026-05-30.jsonl" ]
  jq -e '.ts == "2026-05-31T00:00:01Z"' "$WALTER_CONFIG/audit/chain-2026-05-31.jsonl"
}

@test "B-1: append preserves caller RETURN traps" {
  marker="$TMP_HOME/caller-return-trap-ran"

  run bash -c "
    source '$AUDIT_LIB'
    caller_with_trap() {
      trap \"printf ran > '$marker'\" RETURN
      walter_audit_append Bash ls allow approval-gate ok >/dev/null
    }
    caller_with_trap
  "

  [ "$status" -eq 0 ]
  [ -f "$marker" ]
  [ "$(cat "$marker")" = "ran" ]
}
