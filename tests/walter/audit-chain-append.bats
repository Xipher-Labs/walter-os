#!/usr/bin/env bats
# tests/walter/audit-chain-append.bats
#
# OSS Trust B-1 audit-chain writer coverage.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT_LIB="$REPO_ROOT/scripts/walter/lib/audit-chain.sh"
  SESSION_LIB="$REPO_ROOT/scripts/walter/lib/session-state.sh"
  TMP_HOME="$(mktemp -d "$REPO_ROOT/.tmp-audit-chain.XXXXXX")"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/home/.config/walter-os"
  export WALTER_AUDIT_DATE="2026-05-31"
  export WALTER_AUDIT_NOW="2026-05-31T12:00:00Z"
  export WALTER_SESSION_TEST_CLOCK=1
  export WALTER_SESSION_NOW_EPOCH=1767225600
  export WALTER_OS_HOME="$REPO_ROOT"
  mkdir -p "$WALTER_CONFIG"
  bash -c "source '$SESSION_LIB'; _walter_session_openssl" >/dev/null \
    || skip "ED25519-capable openssl required"
  bash -c "source '$SESSION_LIB'; walter_session_touch '$REPO_ROOT'" >/dev/null
  state_file="$(bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_ROOT'")"
  export WALTER_SESSION_ID="$(jq -r '.session_id' "$state_file")"
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

_root_path() {
  printf '%s/audit/root-2026-05-31.txt\n' "$WALTER_CONFIG"
}

_physical_path() {
  (cd "$1" && pwd -P)
}

_mode_of() {
  if stat -f %Lp "$1" >/dev/null 2>&1; then
    stat -f %Lp "$1"
  else
    stat -c %a "$1"
  fi
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
  run bash -c "umask 022; source '$AUDIT_LIB'; walter_audit_append Bash 'cat README.md' allow approval-gate 'standing approval'"

  [ "$status" -eq 0 ]
  [ "$output" = "$(_chain_path)" ]
  [ -f "$(_chain_path)" ]
  [ -f "$(_root_path)" ]
  [ "$(_mode_of "$WALTER_CONFIG/audit")" = "700" ]
  [ "$(_mode_of "$(_chain_path)")" = "600" ]
  [ "$(_mode_of "$(_root_path)")" = "600" ]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "1" ]
  [ "$(cat "$(_root_path)")" = "$(_sha256 "$(sed -n '1p' "$(_chain_path)")")" ]
  jq -e '.prev_hash == "null"' "$(_chain_path)"
  jq -e '.row_hash | test("^[0-9a-f]{64}$")' "$(_chain_path)"
  jq -e '.sig | test("^[A-Za-z0-9+/]{86}==$")' "$(_chain_path)"
  jq -e '.tool == "Bash" and .decision == "allow" and .decision_source == "approval-gate"' "$(_chain_path)"
}

@test "B-1: flock lock file is private when flock is available" {
  command -v flock >/dev/null 2>&1 || skip "flock not installed"

  run bash -c "umask 022; source '$AUDIT_LIB'; walter_audit_append Bash 'cat README.md' allow approval-gate ok >/dev/null"

  [ "$status" -eq 0 ]
  [ "$(_mode_of "$WALTER_CONFIG/audit/.chain.lock")" = "600" ]
}

@test "B-1: mkdir lock fallback creates private lock directory" {
  lock_dir="$WALTER_CONFIG/audit/.chain.lock"
  mkdir -p "$WALTER_CONFIG/audit"

  run bash -c "
    umask 022
    source '$AUDIT_LIB'
    _walter_audit_acquire_lock_dir '$lock_dir' 1
    if stat -f %Lp '$lock_dir' >/dev/null 2>&1; then
      mode=\"\$(stat -f %Lp '$lock_dir')\"
    else
      mode=\"\$(stat -c %a '$lock_dir')\"
    fi
    _walter_audit_release_lock '$lock_dir'
    printf '%s' \"\$mode\"
  "

  [ "$status" -eq 0 ]
  [ "$output" = "700" ]
  [ ! -d "$lock_dir" ]
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

@test "B-1: append truncates stale fd before retrying post-write rotation" {
  bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'before rotation' allow approval-gate ok >/dev/null"

  run bash -c "
    source '$AUDIT_LIB'
    check_count=0
    _walter_audit_fd_matches_path() {
      check_count=\$((check_count + 1))
      if [[ \"\$check_count\" -eq 2 ]]; then
        mv '$(_chain_path)' '$(_chain_path).rotated-after-write'
        return 1
      fi
      return 0
    }
    walter_audit_append Bash 'after post-write rotation' allow approval-gate ok
  "

  [ "$status" -eq 0 ]
  [ -f "$(_chain_path)" ]
  [ -f "$(_chain_path).rotated-after-write" ]
  [ "$(wc -l < "$(_chain_path).rotated-after-write" | tr -d ' ')" = "1" ]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "1" ]
  jq -e '.input_summary == "before rotation"' "$(_chain_path).rotated-after-write"
  jq -e '.prev_hash == "null" and .input_summary == "after post-write rotation"' "$(_chain_path)"
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
  bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31 >/dev/null"
}

@test "B-2: jq-free first row resolves session id from state file" {
  expected_session_id="$WALTER_SESSION_ID"
  mkdir -p "$TMP_HOME/mock-bin"
  cat > "$TMP_HOME/mock-bin/jq" <<'SH'
#!/usr/bin/env bash
exit 42
SH
  chmod +x "$TMP_HOME/mock-bin/jq"

  run bash -c "source '$AUDIT_LIB'; unset WALTER_SESSION_ID; WALTER_AUDIT_REPO='$REPO_ROOT' PATH='$TMP_HOME/mock-bin':\$PATH walter_audit_append Bash 'jq missing input' block approval-gate 'jq missing'"

  [ "$status" -eq 0 ]
  jq -e --arg session_id "$expected_session_id" '.session_id == $session_id' "$(_chain_path)"
  bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31 >/dev/null"
}

@test "B-2: jq-free session fallback reports missing python3" {
  mkdir -p "$TMP_HOME/mock-bin"
  cat > "$TMP_HOME/mock-bin/jq" <<'SH'
#!/usr/bin/env bash
exit 42
SH
  cat > "$TMP_HOME/mock-bin/python3" <<'SH'
#!/usr/bin/env bash
exit 127
SH
  chmod +x "$TMP_HOME/mock-bin/jq" "$TMP_HOME/mock-bin/python3"

  run bash -c "source '$AUDIT_LIB'; unset WALTER_SESSION_ID; WALTER_AUDIT_REPO='$REPO_ROOT' PATH='$TMP_HOME/mock-bin':\$PATH walter_audit_append Bash 'jq missing input' block approval-gate 'jq missing'"

  [ "$status" -eq 3 ]
  [[ "$output" == *"required tool missing: python3"* ]]
  [ ! -s "$(_chain_path)" ]
  [ ! -f "$(_root_path)" ]
}

@test "B-2: append signs with the resolved row session id" {
  expected_session_id="$WALTER_SESSION_ID"

  run bash -c "
    source '$AUDIT_LIB'
    session_resolution_count=0
    _walter_audit_current_session_id() {
      session_resolution_count=\$((session_resolution_count + 1))
      if [[ \"\$session_resolution_count\" -eq 1 ]]; then
        printf '%s' '$expected_session_id'
      else
        printf '%s' rotated-session
      fi
    }
    walter_audit_append Bash 'session race' allow approval-gate ok
  "

  [ "$status" -eq 0 ]
  jq -e --arg session_id "$expected_session_id" '.session_id == $session_id' "$(_chain_path)"
  bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31 >/dev/null"
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
  bash -c "source '$AUDIT_LIB'; walter_audit_verify_chain 2026-05-31 >/dev/null"
}

@test "B-2: signing fails closed when temp directory creation fails" {
  mkdir -p "$TMP_HOME/mock-bin"
  cat > "$TMP_HOME/mock-bin/mktemp" <<'SH'
#!/usr/bin/env bash
exit 42
SH
  chmod +x "$TMP_HOME/mock-bin/mktemp"

  run bash -c "source '$AUDIT_LIB'; PATH='$TMP_HOME/mock-bin':\$PATH walter_audit_append Bash 'cat README.md' allow approval-gate ok"

  [ "$status" -eq 1 ]
  [[ "$output" == *"temporary directory unavailable"* ]]
  if [[ -f "$(_chain_path)" ]]; then
    [ ! -s "$(_chain_path)" ]
  fi
}

@test "B-1: dependency failure rows without jq cannot extend existing chains" {
  bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'first row' block approval-gate ok >/dev/null"
  mkdir -p "$TMP_HOME/mock-bin"
  cat > "$TMP_HOME/mock-bin/jq" <<'SH'
#!/usr/bin/env bash
exit 42
SH
  chmod +x "$TMP_HOME/mock-bin/jq"

  run bash -c "source '$AUDIT_LIB'; PATH='$TMP_HOME/mock-bin:/usr/bin:/bin' walter_audit_append Bash 'jq missing input' block approval-gate 'jq missing'"

  [ "$status" -eq 1 ]
  [[ "$output" == *"jq required to append to existing chain"* ]]
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" = "1" ]
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

@test "B-1: append rejects empty chain when root already exists" {
  bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'first row' allow approval-gate ok >/dev/null"
  original_root="$(cat "$(_root_path)")"
  : > "$(_chain_path)"

  run bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'after truncation' allow approval-gate ok"

  [ "$status" -eq 1 ]
  [[ "$output" == *"empty chain with existing root"* ]]
  [ ! -s "$(_chain_path)" ]
  [ "$(cat "$(_root_path)")" = "$original_root" ]
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

@test "B-2: hook cwd is existing directory normalized before export" {
  mkdir -p "$TMP_HOME/repo/child"
  physical="$(_physical_path "$TMP_HOME/repo")"
  hook_input="$(jq -n --arg cwd "$TMP_HOME/repo/child/.." '{"cwd":$cwd}')"

  run bash -c "source '$AUDIT_LIB'; walter_audit_set_repo_from_hook_input '$hook_input'; printf '%s' \"\${WALTER_AUDIT_REPO:-}\""

  [ "$status" -eq 0 ]
  [ "$output" = "$physical" ]
}

@test "B-2: hook cwd ignores nonexistent directories" {
  hook_input="$(jq -n --arg cwd "$TMP_HOME/missing" '{"cwd":$cwd}')"

  run bash -c "source '$AUDIT_LIB'; walter_audit_set_repo_from_hook_input '$hook_input'; printf '%s' \"\${WALTER_AUDIT_REPO:-unset}\""

  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}
